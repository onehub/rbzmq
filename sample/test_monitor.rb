require "zmq"

context = ZMQ::Context.new(1)

puts "Setting up connection for READ"
inbound = context.socket(ZMQ::UPSTREAM)
puts "Setting up monitor"
monitor = inbound.monitor(ZMQ::EVENT_ALL)
inbound.bind("tcp://127.0.0.1:9000")

outbound = context.socket(ZMQ::DOWNSTREAM)
outbound.connect("tcp://127.0.0.1:9000")
p outbound.send("Hello World!")
p outbound.send("Is anyone there?")
p outbound.send("QUIT")

closed = false;
loop do
  # Because we'll be closing this socket first:
  if (closed != true)
    # We're doing a poll loop since we're watching two sockets
    data = inbound.recv(ZMQ::DONTWAIT)
    if (data)
      p data
      if (data == "QUIT")
        outbound.close
        inbound.close
        closed = true
      end
    end
  end
  flag = monitor.recv(ZMQ::DONTWAIT)
  if (flag)
    if (flag == ZMQ::EVENT_LISTENING)
      p "FLAG: EVENT_LISTENING"
    elsif (flag == ZMQ::EVENT_ACCEPTED)
      p "FLAG: EVENT_ACCEPTED"
    elsif (flag == ZMQ::EVENT_ACCEPT_FAILED)
      p "FLAG: EVENT_ACCEPT_FAILED"
    elsif (flag == ZMQ::EVENT_CONNECTED)
      p "FLAG: EVENT_CONNECTED"
    elsif (flag == ZMQ::EVENT_CONNECT_DELAYED)
      p "FLAG: EVENT_CONNECT_DELAYED"
    elsif (flag == ZMQ::EVENT_BIND_FAILED)
      p "FLAG: EVENT_BIND_FAILED"
    elsif (flag == ZMQ::EVENT_CLOSE_FAILED)
      p "FLAG: EVENT_CLOSE_FAILED"
    elsif (flag == ZMQ::EVENT_CLOSED)
      p "FLAG: EVENT_CLOSED"
      # Socket's been closed, nothing else is going to happen at this point
      break
    elsif (flag == ZMQ::EVENT_DISCONNECTED)
      p "FLAG: EVENT_ACCEPTED"
    else
      p "OTHER FLAG: #{flag}"
    end
  end
  # We don't need to be super-realtime here
  sleep 1
end
