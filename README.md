# TCP Urgent Data Mode and the Ruby Socket Library

This repository contains several code snippets, which show the usage of
the *TCP Urgent Data Mode* in Ruby (tested with 1.9.3).

## Background

To learn about the *TCP Urgent Data* mode it is best to study "UNIX Network 
Programming - The Sockets Networking API" by W. Richard Stevens & al
(Addison-Wesley). The chapter "Out-of-Band Data" discusses in great details
all the possibilities and challenges of this technique. 
Of course, this book shows its examples in C. 

## "Out-of-Band" Data and the Urgent Pointer

TCP allows to send some data *faster* to the receiver, quasi by *overtaking*
the already sent stream. This concept is called *out-of-band* (or
*expedited*) data.

The **Socket#send** method allows to send one(!) byte of out-of-band data
by using the MSG_OOB flag:

      socket.send(oob_char, Socket::MSG_OOB)

TCP places this data in the next available position in the socket send buffer, 
sets the URG flag and the *urgent pointer* next to this location. 
It's up to the receiver to properly handle this out-of-band mode.

### urg_send.rb

This little send client will be used to test all the different receiver 
servers. We send some data in a loop with a pause of one second in between.
To send the out-of-band data the user will press Ctrl-C. The handler of this
signal does the actual urgent send.

      require 'socket'

      host = 'localhost'
      port = 4481
      oob_char = '!'
    
      socket = Socket.tcp(host, port)

      trap(:INT) do
        socket.send(oob_char, Socket::MSG_OOB)
      end

      ('aa'..'az').each do |chars|
        socket.puts(chars)
        sleep(1)                  # wait some time for comfortable testing
      end

The file urg_send.rb the repository contains (as all the different 
server examples) some additional code for command line parameter 
collection, exception handling and informational output.

NB: All the example scripts are somehow influenced by the corresponding chapter
in "Network Programming with Perl" by Lincoln D. Stein (Addison-Wesley), 
adapted to the needs and possibilities of Ruby.

## Using the URG Signal

When a server receives a TCP stream with the URG flag set, the operating system
will generate a SIGURG signal. Within the handler of this signal the
**Socket#recv** method can read the out-of-band data byte with the
MSG_OOB flag:

      trap(:URG) do
        data = socket.recv(100, Socket::MSG_OOB)
      end 

To catch this signal, it is necessary to set the owner of the socket with the 
**Socket#fcntl** method:

      socket.fcntl(F_SETOWN, Process.pid)
      
The challenge here is, that the Ruby *Fcntl* library module does not contain 
the F_SETOWN constant. Sneaking into the C include file *fcntl.h* we learn that
it should be set to 6.

### urg_recv1.rb

Our first variant of a receiver server uses the URG signal:

      require 'socket'

      F_SETOWN = 6    # set manual as not defined in Fcntl
      port = 4481

      Socket.tcp_server_loop(port) do |socket|
        trap(:URG) do
          data = socket.recv(100, Socket::MSG_OOB)
        end

        socket.fcntl(F_SETOWN, Process.pid)   # so we will get sigURG
        while data = socket.gets do
          data.chop!
          puts "got %d bytes of normal data: %s" % [data.size, data]
        end  
      end

Here the essential parts of the log of executing this client/server pair:

    Client:
    iMac$ ruby urg_send.rb
    OOB Character: "!"
    ...
    sending 2 bytes of normal data: ag
    sending 2 bytes of normal data: ah
    ^Csending 1 byte of OOB data: "!"
    sending 2 bytes of normal data: ai
    sending 2 bytes of normal data: aj
    ...

    Server:
    iMac$ ruby urg_recv1.rb 
    waiting for connections on port 4481
    incoming connection from 127.0.0.1:51393
    ...
    got 2 bytes of normal data: ag
    got 1 bytes of urgent data: !
    got 2 bytes of normal data: ah
    got 2 bytes of normal data: ai
    got 2 bytes of normal data: aj
    ...

If the client and the server agree about the meaning of different oob 
characters, these can be used for some urgent mode steering.

## The SO_OOBINLINE Option

If we want the urgent data to stay within the normal data, we can use the 
**Socket#setsockopt** method with the SO_OOBINLINE option:

    socket.setsockopt(:SOCKET, Socket::SO_OOBINLINE, true)

We will still get the URG signal, but calling *recv()* with MSG_OOB will return 
an EINVAL error.

###urg_recv2.rb

Our second variant of a receiver server uses the SO_OOBINLINE option:

      require 'socket'

      F_SETOWN = 6
      port = 4481

      Socket.tcp_server_loop(port) do |socket|

        trap(:URG) do
          begin
            data = socket.recv(100, Socket::MSG_OOB)
          rescue Exception => err
            puts "expected recv() error: %s" % err.inspect
          end
        end

        # enable inline urgent data 
        socket.setsockopt(:SOCKET, Socket::SO_OOBINLINE, true)
  
        socket.fcntl(F_SETOWN, Process.pid)   # so we will get sigURG
        while data = socket.gets do
          data.chop!
          puts "got %d bytes of normal data: %s" % [data.size, data]
        end
      end

Here the essential parts of the log of executing this client/server pair:

      Client:
      iMac$ ruby urg_send.rb
      OOB Character: "!"
      connected to 127.0.0.1:4481
      ...
      sending 2 bytes of normal data: af
      sending 2 bytes of normal data: ag
      ^Csending 1 byte of OOB data: "!"
      sending 2 bytes of normal data: ah
      sending 2 bytes of normal data: ai
      ...

      Server:
      iMac$ ruby urg_recv2.rb 
      waiting for connections on port 4481
      incoming connection from 127.0.0.1:51407
      ...
      got 2 bytes of normal data: af
      expected recv() error: #<Errno::EINVAL: Invalid argument - recvfrom(2)>
      got 2 bytes of normal data: ag
      got 3 bytes of normal data: !ah
      got 2 bytes of normal data: ai
      ...

As the oob message is not snt with some framing, we see the oob 
character as part of normal data.

## Using select() with Urgent Data

Instead of using the URG signal to steer the urgent data read,
we can also control it with the **IO::select** method. 
The third parameter of *select()* is used for this exceptional data:

      (has_read, can_write, has_urgent) = IO.select(read_a, write_a, except_a)
      
But there is a challenge: calling *recv()* with MSG_OOB a second time before reading normal data will return an EINVAL error. This condition has to be avoided by the program logic.

### urg_recv3.rb

Our third variant of a receiver server uses select():   

      require 'socket'

      port = 4481
      Socket.tcp_server_loop(port) do |socket|
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
            data.chop!
            puts "got %d bytes of normal data: %s" % [data.size, data]
            ok_to_read_oob = true   # now urgent recv() again possible
          end
        end
      end

Instead of looping on *has_urgent* and *has_regular*, 
we just get the first element of these arrays by **Array#shift** as there
is in this example only one socket.

Here the essential parts of the log of executing this client/server pair:

      Client:
      iMac$ ruby urg_send.rb
      OOB Character: "!"
      connected to 127.0.0.1:4481
      ...
      sending 2 bytes of normal data: ah
      sending 2 bytes of normal data: ai
      ^Csending 1 byte of OOB data: "!"
      sending 2 bytes of normal data: aj
      sending 2 bytes of normal data: ak
      ...

      Server:
      iMac$ ruby urg_recv3.rb 
      waiting for connections on port 4481
      incoming connection from 127.0.0.1:51415
      ...
      got 2 bytes of normal data: ah
      got 2 bytes of normal data: ai
      got 1 bytes of urgent data: "!"
      got 2 bytes of normal data: aj
      got 2 bytes of normal data: ak

## Discard the marked Section of Data

A common use of the urgent data mode is to mark previous sent data in the TCP
stream as invalid and discard them. It is possible to use the SO_OOBINLINE
option (either with the URG signal or *select()*) to scan the data for a 
known oob character and refrain to deliver the section before a match to
the user. But this approach is not a good idea: 

  - the oob character must be known to the server
  - the normal data may not contain this character and
  - there may be multiple copies of the oob character as the client can send
   more than one urgent data message before the server handles them
  
The solution for this challenge is to use a *sockatmark(fileno)* function
which returns 1 when at the out-of-band mark or 0 if not at mark. Together with
the feature, that *Socket#readpartial* (or *sysread()*) pauses at the
out-of-band mark, this can be used by the receiver to collect the data until 
the mark is passed and treat it special.

Unfortunately, a *Socket#sockatmark* method is not available in the Ruby 
*Socket* library. And the workaroud with *Socket#ioctl* with the operation
SIOCATMARK (as used by Lincoln Stein in above mentioned Perl book) is not
supported in Ruby.

### sockatmark.c

As a last resort we can write a C-extension for Ruby. 

      #include "ruby.h"
      #include "stdio.h"
      #include "sys/ioctl.h"
      #include "sys/socket.h"

      static VALUE t_atmark(VALUE self, VALUE fnum)
      {
        int fd;
        int flag;
        int result;

        fd = NUM2INT(fnum);
        result = ioctl(fd, SIOCATMARK, &flag);
        if (result < 0)
          return(-1);
        return INT2NUM(flag);
      }

      VALUE cAtMark;
      void Init_sockatmark()
      {
        cAtMark = rb_define_class("AtMark", rb_cObject);
        rb_define_method(cAtMark, "atmark", t_atmark, 1);
      }

This code defines a class *AtMark* with an instance method *AtMark#atmark* 
with the desired behavior described above.

As next step we have to write a little script "extconf.rb":

      require 'mkmf'
      create_makefile("sockatmark")
      
Executing this file will generate a "Makefile". And calling on the command
line its default action with "make" generates a "sockatmark.o" and (on Mac OSX) 
a "sockatmark.bundle", which can be requested in a ruby script.

### urgent_data.rb

This class encapsulates the urgent data handling with our solution of
*sockatmark()*. 

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
          require_relative 'sockatmark'   # C-extenstion
    
          def data?
            return @data.size > 0
          end
    
          def initialize(connection)
            @sock = connection            # connection to read from
            @data = ""                    # start with an empty buffer
            @atm = AtMark.new             # class for sockatmark
            @pid = Process.pid          
          end # initialize
    
          def lines(separator=$/)
            ok_to_read_oob = false        # flag to avoid recv() error EINVAL
            sock_arr = [@sock]            # for select() read array
      
            loop do  
              # prepare the error array in dependence of the OOB state
              except_arr = ok_to_read_oob ? sock_arr : []
        
              # we don't want to block as long as we have data available
              # but also don't want to miss any incoming normal/urgent data
              # we use the can_write array to cause immediate return if required
              # and block with select when we dont have anything to yield
              keep_alive_arr = data? ? sock_arr : []
      
              (has_regular, _, has_urgent) = 
                                IO.select(sock_arr, keep_alive_arr, except_arr)
  
              if sock = has_urgent.shift
                # read the oob charatcer
                oob = sock.recv(BUFF_SIZE, Socket::MSG_OOB)
                ok_to_read_oob = false

                until (atm = @atm.atmark(sock.fileno)) == 1
                  raise IOCTL if atm == -1
                  # forward read until urgent pointer
                  begin
                    @data << @sock.readpartial(BUFF_SIZE) 
                  rescue EOFError
                    raise EOF
                  end
                end
          
                @data = ''                  # flush the discarded data
                raise OOB
                break
              end # has urgent

              if sock = has_regular.shift
                begin
                  data = sock.readpartial(BUFF_SIZE)
                rescue EOFError
                  info "remote closed connection"
                  raise EOF
                  break
                end

                # append to intermediate buffer
                @data << data
                ok_to_read_oob = true                        
              end # has regular
              
              if data?    
                if index = @data.index(separator)
                  # something to deliver
                  line = @data.slice!(0,index)      # get the next line
                  @data.slice!(0,separator.size)    # get rid of the separator
                  
                  yield(line) if block_given?
                end
              end
            end # loop
          end # lines  
        end # Urgent
      end # UgentData

As the sockatmark function works on low level IO (#sysread or #readpartial)
and we want to use "framed" IO (like *Socket#gets*) we have to do that 
logic ourself (by also using *Socket#readpartial* and scanning an intermediate
data buffer with *String#index* for the next separator). But the logic together
with *IO::select* gets a little bit tricky

### urg_recv4.rb

Finally our forth variant of a receiver server uses the above wrapper in
a forked environment:

      require 'socket'
      require_relative 'urgent_data/urgent_data'

      port = 4481

      server_socket = TCPServer.new(port)

      loop do
        connection_socket = server_socket.accept
        pid = fork do
          lines = 0
          urgent = UrgentData::Urgent.new(connection_socket)
          begin
            urgent.lines do |line|
              lines += 1
              puts "yielded line: %s" % line
              sleep 3         # to emulate heavy work
            end
          rescue UrgentData::OOB
            puts "UrgentData::OOB - seen %d lines" % lines
            puts
            puts
            lines = 0
            retry             # to keep the test running
          rescue UrgentData::EOF
            puts "UrgentData::EOF - seen %d lines" % lines
            connection_socket.close
          end
        end # forked process
        Process.detach(pid)
      end
      
Here the essential parts of the log of executing this client/server pair:

      Client:
      iMac$ ruby urg_send.rb
      OOB Character: "!"
      connected to 127.0.0.1:4481
      sending 2 bytes of normal data: aa
      sending 2 bytes of normal data: ab
      sending 2 bytes of normal data: ac
      sending 2 bytes of normal data: ad
      sending 2 bytes of normal data: ae
      sending 2 bytes of normal data: af
      sending 2 bytes of normal data: ag
      ^Csending 1 byte of OOB data: "!"
      sending 2 bytes of normal data: ah
      sending 2 bytes of normal data: ai
      ...

      Server:
      iMac$ ruby urg_recv4.rb 
      waiting for connection on port 4481
      yielded line: aa
      yielded line: ab
      yielded line: ac
      UrgentData::OOB - seen 3 lines


      yielded line: ah
      yielded line: ai
      ...

This solution delivers the urgent data functionality to the user with the 
expected Ruby elegance.
