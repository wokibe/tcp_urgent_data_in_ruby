# urgent data receiver server with SO_OOBINLINE
# file: urg_recv2.rb
# usage: urg_recv2.rb <port>
# to be tested with urg_send.rb

require 'socket'

F_SETOWN = 6    # set manual as not defined in Fcntl

port = ARGV.shift || 4321

trap(:INT) { exit }

puts "waiting for connections on port %d" % port
Socket.tcp_server_loop(port) do |socket|
  puts "incoming connection from %s" % socket.remote_address.inspect_sockaddr

  trap(:URG) do
    begin
      data = socket.recv(100, Socket::MSG_OOB)
      puts "got %d bytes of urgent data: %s" % [data.size, data]
    rescue Exception => err
      puts "expected recv() error: %s" % err.inspect
    end
  end

  # enable inline urgent data 
  socket.setsockopt(:SOCKET, Socket::SO_OOBINLINE, true)
  
  socket.fcntl(F_SETOWN, Process.pid)   # so we will get sigURG
  while data = socket.gets do
    if socket.eof?
      puts "remote closed connection"
      socket.close
      break
    end
    data.chop!
    puts "got %d bytes of normal data: %s" % [data.size, data]
  end
  
end