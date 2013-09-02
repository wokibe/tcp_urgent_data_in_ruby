# urgent data receiver module with:
#     select() and an emulated sockatmark
# file: urgent_data.rb
# usage: to be required from a urgent data server

module UrgentData

  class EOF < StandardError
  # raised when reading nil
  end
  
  class OOB < StandardError
  # raised when seen the OOB character
  end
  
  class IOCTL < StandardError
  # raised when Atm#atmark returns an error (-1)
  end
  
  class Urgent

    BUFF_SIZE = 1024
    
    require 'socket'
    require_relative 'sockatmark' # C-extenstion
    
    # as the sockatmark logic works on lowlevel IO (#sysread or #readpartial)
    # and we want to use "framed" IO (#gets) we have to do that logic ourself
    
    def info(txt)
      puts "%5d: %s" % [@pid, txt] if @verbose
    end
    
    def dbug(txt)
      puts "%5d: %s" % [@pid, txt] if @debug
    end
    
    def data?
      return @data.size > 0
    end
    
    def initialize(connection, verbose = false, debug = false)
      @sock = connection            # connection to read from
      @data = ""                    # start with an empty buffer
      @atm = AtMark.new             # class for sockatmark
      @pid = Process.pid          
      @verbose = verbose            # generate info output if true
      @debug = debug                # generate dbug output if true
      
      info "connection from %s" % @sock.remote_address.inspect_sockaddr     
    end # initialize
    
    def lines(separator=$/)
      ok_to_read_oob = false        # flag to avoid recv() error EINVAL
      sock_arr = [@sock]            # for select() read array
      
      loop do  
        # prepare the error array in dependence of the OOB state
        except_arr = ok_to_read_oob ? sock_arr : []
        
        # we don't want to block as long as we have data available
        # but also don't want to miss any incoming normal/urgent data
        # so we use the can_write array to cause immediate return if required
        # and block with select when we dont have anything to yield
        keep_alive_arr = data? ? sock_arr : []
        
        (has_regular, _, has_urgent) = 
                              IO.select(sock_arr, keep_alive_arr, except_arr)
  
        if sock = has_urgent.shift
          dbug "has urgent"
          info "select() indicated oob data"
          begin     # try to read the oob charatcer
            oob = sock.recv(BUFF_SIZE, Socket::MSG_OOB)
            dbug "recv(MSG_OOB) retured: %s" % oob
          rescue Exception => err
            info "recv(MSG_OOB) returned an error %s" % err.inspect
          end
          ok_to_read_oob = false

          info "we will flash data before the urgent pointer"
                    
          until (atm = @atm.atmark(sock.fileno)) == 1
            dbug "atmark: %d" % atm
            raise IOCTL if atm == -1
            # forward read until urgent pointer
            begin
              dbug "data before readpartial(): %d - %s" % [@data.size, @data]
              @data << @sock.readpartial(BUFF_SIZE) 
              dbug "data after readpartial():  %d - %s" % [@data.size, @data]
            rescue EOFError
              info "remote closed connection"
              raise EOF
            end
          end
          
          dbug "flushing %d bytes of pre oob data: %s" % [@data.size, @data]
          @data = ''
          raise OOB
          break
        end # has urgent

        if sock = has_regular.shift
          dbug "has regular"
          atm = @atm.atmark(sock.fileno)
          dbug "atmark: %d" % atm
          dbug "data before readpartial(): %d - %s" % [@data.size, @data]
          begin
            data = sock.readpartial(BUFF_SIZE)
          rescue EOFError
            info "remote closed connection"
            raise EOF
            break
          end

          atm = @atm.atmark(sock.fileno)
          dbug "atmark: %d" % atm

          # append to intermediate buffer
          @data << data
          dbug "data after readpartial():  %d - %s" % [@data.size, @data]

          ok_to_read_oob = true                        
        end # has regular
        
        if data?
          if index = @data.index(separator)
            # something to deliver
            line = @data.slice!(0,index)      # get the next line
            info "got %d bytes of normal data: %s" % [line.size, line]
            @data.slice!(0,separator.size)    # get rid of the separator
            
            yield(line) if block_given?
          end
        end
      end # loop
    end # lines  
  end # Urgent
end # UgentData
