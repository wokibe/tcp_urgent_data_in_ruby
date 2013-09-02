# forked urgent_data server 
# file: urg_recv4.rb
# usage: urg_recv4.rb <port> 
# to be tested with urg_send.rb

require 'socket'
require_relative 'urgent_data/urgent_data'

port = ARGV.shift || 4321

trap(:INT) { exit }

puts "waiting for connection on port %d" % port
            
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
      retry
    rescue UrgentData::EOF
      puts "UrgentData::EOF - seen %d lines" % lines
      connection_socket.close
    end
  end # forked process
  Process.detach(pid)
end            
