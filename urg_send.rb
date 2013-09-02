# simple urgent data sender client
# to test urg_recv*.rb
#
# file: urg_send.rb
# usage: urg_sen.rb <host> <port> <oob_char>

require 'socket'

OOB_CHAR = '!'

host = ARGV.shift || 'localhost'
port = ARGV.shift || 4321
oob_char = ARGV.shift || OOB_CHAR

# allow all unsigned byte characters
oob_char = [oob_char.to_i].pack("C") if oob_char =~ /^\d+$/
oob_char = oob_char[0]

puts "OOB Character: %s" % oob_char.inspect 
socket = Socket.tcp(host, port)
puts "connected to %s" % socket.remote_address.inspect_sockaddr

trap(:INT) do
  puts "sending 1 byte of OOB data: %s" % oob_char.inspect
  socket.send(oob_char, Socket::MSG_OOB)
end

trap(:QUIT) { exit 0 }

('aa'..'az').each do |chars|
  puts "sending %d bytes of normal data: %s" % [chars.size, chars]
  begin
    socket.puts(chars)
  rescue Errno::EPIPE
    puts "remote closed socket"
    exit
  end
  sleep(1)      # wait some time for comfortable testing
end

puts "press Ctrl-\ to terminate"
sleep(60)      # keep the socket open to let the server finish
