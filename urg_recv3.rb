# urgent data receiver server with select()
# file: urg_recv3.rb
# usage: urg_recv3.rb <port> 
# to be tested with urg_send.rb

require 'socket'

port = ARGV.shift || 4321

trap(:INT) { exit }

puts "waiting for connections on port %d" % port
Socket.tcp_server_loop(port) do |socket|
  puts "incoming connection from %s" % socket.remote_address.inspect_sockaddr
  
  ok_to_read_oob = true         # flag to avoid recv() error EINVAL
  sock_arr = [socket]

  loop do  
    # prepare third select() parameter
    except_arr = ok_to_read_oob ? sock_arr : []

    (has_regular, _, has_urgent) = IO.select(sock_arr, nil, except_arr)
  
    if sock = has_urgent.shift
      begin
        data = sock.recv(100, Socket::MSG_OOB)
        puts "got %d bytes of urgent data: %s" % [data.size, data.inspect]
      rescue Exception => err
        puts err.inspect
      end
      ok_to_read_oob = false  # wait until next regular read
    end

    if sock = has_regular.shift
      data = sock.gets

      if data.nil?
        puts "remote closed connection"
        sock.close
        break
      end

      data.chop!
      puts "got %d bytes of normal data: %s" % [data.size, data]
      ok_to_read_oob = true   # now urgent recv() again possible
    end
  end
end