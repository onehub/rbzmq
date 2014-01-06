require "zmq"

# Requires rspec gem (obviously)
#
# To run the tests, run "rspec" in the spec parent directory.  That's it.

describe "rbzmq tests" do
  let(:context) { ZMQ::Context.new(1) }

  context "basic tests" do
    it "opens and closes a connection without error" do
      inbound = context.socket(ZMQ::PULL)
      inbound.bind("tcp://127.0.0.1:9000").should == nil
      inbound.close.should == nil
    end

    it "can connect to both ends of a connection and close without error" do
      inbound = context.socket(ZMQ::PULL)
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      outbound = context.socket(ZMQ::PUSH)
      outbound.connect("tcp://127.0.0.1:9000").should == nil

      outbound.close.should == nil
      inbound.close.should == nil
    end

    it "can successfully communicate over a socket" do
      inbound = context.socket(ZMQ::PULL)
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      outbound = context.socket(ZMQ::PUSH)
      outbound.connect("tcp://127.0.0.1:9000").should == nil

      outbound.send("hello world!").should == true
      outbound.send("goodbye, cruel world!").should == true
      # TODO: figure out a clean way to time this out in case something goes wrong;
      # this could block forever.  The Timeout object, alas, is not a solution; it
      # will not timeout as long as the ruby thread is blocked for the recv.  This
      # goes for all the recv calls (and potentially for the loops as well, since
      # they contain blocking recv; the generic Timeout object would only work on
      # the first loop test below, so is not a general solution.

      # We could simply wrap a poll loop inside a timeout and use
      # recv(ZMQ::DONTWAIT), but then we wouldn't actually be testing the normal
      # recv use case.  Alternately, maybe we could do some sort of heavyweight
      # daughter thread madness?

      # Alternately: we could ignore the whole issue (NOTE: not an option if this
      # ends up in CI?) and just assume that tests will pass and nothing will block
      # on passing tests.
      data = inbound.recv()
      data.should == "hello world!"
      data = inbound.recv()
      data.should == "goodbye, cruel world!"

      outbound.close.should == nil
      inbound.close.should == nil
    end

    it "can reconnect to broken socket" do
      # This is new with ZMQ3.0; connections should reconnect automatically (i.e.,
      # without any action on our part) if a connection goes down and is recreated;
      # this test tests that.
      inbound = context.socket(ZMQ::PULL)
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      outbound = context.socket(ZMQ::PUSH)
      outbound.connect("tcp://127.0.0.1:9000").should == nil

      outbound.send("hello world!").should == true
      data = inbound.recv()
      data.should == "hello world!"

      inbound.close.should == nil
      inbound = context.socket(ZMQ::PULL)
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      outbound.send("I'm back!").should == true
      data = inbound.recv()
      data.should == "I'm back!"

      outbound.close.should == nil
      inbound.close.should == nil
    end
  end # context basic tests

  context "monitor tests" do
    it "opens a monitor socket without error" do
      inbound = context.socket(ZMQ::PULL)
      monitor = inbound.monitor()
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      monitor.close.should == nil
      inbound.close.should == nil
    end

    it "can receive monitor socket events" do
      inbound = context.socket(ZMQ::PULL)
      monitor = inbound.monitor()
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      inbound.close.should == nil

      data = monitor.recv()
      data.should == ZMQ::EVENT_LISTENING
      data = monitor.recv()
      data.should == ZMQ::EVENT_CLOSED
      monitor.close.should == nil
    end

    it "can receive events for two-way connection" do
      # This only tests monitoring events on the inbound (PULL) side of the connection
      inbound = context.socket(ZMQ::PULL)
      monitor = inbound.monitor()
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      outbound = context.socket(ZMQ::PUSH)
      outbound.connect("tcp://127.0.0.1:9000").should == nil

      outbound.send("hello world!").should == true
      data = inbound.recv()
      data.should == "hello world!"

      outbound.close.should == nil
      inbound.close.should == nil

      data = monitor.recv()
      data.should == ZMQ::EVENT_LISTENING
      data = monitor.recv()
      data.should == ZMQ::EVENT_ACCEPTED
      data = monitor.recv()
      data.should == ZMQ::EVENT_CLOSED
      monitor.close.should == nil
    end

    it "can monitor events on other end" do
      # This only tests monitoring events on the outbound (PUSH) side of the connection
      inbound = context.socket(ZMQ::PULL)
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      outbound = context.socket(ZMQ::PUSH)
      monitor = outbound.monitor()
      outbound.connect("tcp://127.0.0.1:9000").should == nil

      outbound.send("hello world!").should == true
      data = inbound.recv()
      data.should == "hello world!"

      data = monitor.recv()
      data.should == ZMQ::EVENT_CONNECT_DELAYED
      data = monitor.recv()
      data.should == ZMQ::EVENT_CONNECTED

      outbound.close.should == nil
      inbound.close.should == nil
      monitor.close.should == nil
    end

    it "can detect broken inbound connection" do
      # This tests the events we get when the inbound (PULL) connection is broken
      # (as seen from the outbound/PUSH side)
      inbound = context.socket(ZMQ::PULL)
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      outbound = context.socket(ZMQ::PUSH)
      monitor = outbound.monitor()
      outbound.connect("tcp://127.0.0.1:9000").should == nil

      outbound.send("hello world!").should == true
      data = inbound.recv()
      data.should == "hello world!"

      inbound.close.should == nil

      data = monitor.recv()
      data.should == ZMQ::EVENT_CONNECT_DELAYED
      data = monitor.recv()
      data.should == ZMQ::EVENT_CONNECTED
      data = monitor.recv()
      data.should == ZMQ::EVENT_DISCONNECTED
      data = monitor.recv()
      data.should == ZMQ::EVENT_CONNECT_RETRIED
      data = monitor.recv()
      data.should == ZMQ::EVENT_CONNECT_DELAYED
      data = monitor.recv()
      data.should == ZMQ::EVENT_CLOSED
      data = monitor.recv()
      data.should == ZMQ::EVENT_CONNECT_RETRIED
      data = monitor.recv()
      data.should == ZMQ::EVENT_CONNECT_DELAYED
      data = monitor.recv()
      data.should == ZMQ::EVENT_CLOSED
      # These three events will continue ad infinitum until outbound is closed
      # (presumably as it tries to reconnect to the missing inbound socket)

      monitor.close.should == nil
      outbound.close.should == nil
    end

    it "can detect broken outbound connection" do
      # This tests the events we get with the outbound (PUSH) connection is broken
      # (as seen from the inbound/PULL side)
      inbound = context.socket(ZMQ::PULL)
      monitor = inbound.monitor()
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      outbound = context.socket(ZMQ::PUSH)
      outbound.connect("tcp://127.0.0.1:9000").should == nil

      outbound.send("hello world!").should == true
      data = inbound.recv()
      data.should == "hello world!"

      outbound.close.should == nil

      data = monitor.recv()
      data.should == ZMQ::EVENT_LISTENING
      data = monitor.recv()
      data.should == ZMQ::EVENT_ACCEPTED
      data = monitor.recv()
      data.should == ZMQ::EVENT_DISCONNECTED

      inbound.close.should == nil

      data = monitor.recv()
      data.should == ZMQ::EVENT_CLOSED

      monitor.close.should == nil
    end

    it "can detect broken inbound/re-connection" do
      # This tests to see what events we get when an inbound (PULL) connection is
      # broken and recreated; this time we monitor both sides, before and after the
      # connection is broken/re-established
      inbound = context.socket(ZMQ::PULL)
      monitor_inbound = inbound.monitor()
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      outbound = context.socket(ZMQ::PUSH)
      monitor_outbound = outbound.monitor()
      outbound.connect("tcp://127.0.0.1:9000").should == nil

      outbound.send("hello world!").should == true
      data = inbound.recv()
      data.should == "hello world!"

      inbound.close.should == nil

      inbound = context.socket(ZMQ::PULL)
      monitor_inbound_new = inbound.monitor()
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      # These will show up on old inbound
      data = monitor_inbound.recv()
      data.should == ZMQ::EVENT_LISTENING
      data = monitor_inbound.recv()
      data.should == ZMQ::EVENT_ACCEPTED
      data = monitor_inbound.recv()
      data.should == ZMQ::EVENT_CLOSED

      # These will show up on new inbound
      data = monitor_inbound_new.recv()
      data.should == ZMQ::EVENT_LISTENING
      data = monitor_inbound_new.recv()
      data.should == ZMQ::EVENT_ACCEPTED

      # These will show up on outbound
      data = monitor_outbound.recv()
      data.should == ZMQ::EVENT_CONNECT_DELAYED
      data = monitor_outbound.recv()
      data.should == ZMQ::EVENT_CONNECTED
      data = monitor_outbound.recv()
      data.should == ZMQ::EVENT_DISCONNECTED
      data = monitor_outbound.recv()
      data.should == ZMQ::EVENT_CONNECT_RETRIED
      data = monitor_outbound.recv()
      data.should == ZMQ::EVENT_CONNECT_DELAYED
      data = monitor_outbound.recv()
      data.should == ZMQ::EVENT_CONNECTED

      monitor_inbound.close.should == nil
      monitor_inbound_new.close.should == nil
      monitor_outbound.close.should == nil
      outbound.close.should == nil
      inbound.close.should == nil
    end

    it "can detect broken outbound/re-connection" do
      # This tests to see what events we get when an outbound (PUSH) connection is
      # broken and recreated; this time we monitor both sides, before and after the
      # connection is broken/re-established
      inbound = context.socket(ZMQ::PULL)
      monitor_inbound = inbound.monitor()
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      outbound = context.socket(ZMQ::PUSH)
      monitor_outbound = outbound.monitor()
      outbound.connect("tcp://127.0.0.1:9000").should == nil

      outbound.send("hello world!").should == true
      data = inbound.recv()
      data.should == "hello world!"

      outbound.close.should == nil

      outbound = context.socket(ZMQ::PUSH)
      monitor_outbound_new = outbound.monitor()
      outbound.connect("tcp://127.0.0.1:9000").should == nil

      # These will show up on inbound
      data = monitor_inbound.recv()
      data.should == ZMQ::EVENT_LISTENING
      data = monitor_inbound.recv()
      data.should == ZMQ::EVENT_ACCEPTED
      data = monitor_inbound.recv()
      data.should == ZMQ::EVENT_DISCONNECTED
      data = monitor_inbound.recv()
      data.should == ZMQ::EVENT_ACCEPTED

      # These will show up on old outbound
      data = monitor_outbound.recv()
      data.should == ZMQ::EVENT_CONNECT_DELAYED
      data = monitor_outbound.recv()
      data.should == ZMQ::EVENT_CONNECTED

      # These will show up on new outbound
      data = monitor_outbound_new.recv()
      data.should == ZMQ::EVENT_CONNECT_DELAYED
      data = monitor_outbound_new.recv()
      data.should == ZMQ::EVENT_CONNECTED

      monitor_inbound.close.should == nil
      monitor_outbound.close.should == nil
      monitor_outbound_new.close.should == nil
      outbound.close.should == nil
      inbound.close.should == nil
    end

    it "can monitor selective socket events" do
      inbound = context.socket(ZMQ::PULL)
      monitor = inbound.monitor(ZMQ::EVENT_CLOSED)
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      inbound.close.should == nil

      data = monitor.recv()
      data.should == ZMQ::EVENT_CLOSED
      monitor.close.should == nil
    end

    it "can monitor multiple types of selective socket events" do
      # This time we're only monitoring the selected events instead of all events
      inbound = context.socket(ZMQ::PULL)

      # Here we select two types of events, below we check to make sure we don't get
      # a third type we'd normally receive (see the two-way example above)
      monitor = inbound.monitor(ZMQ::EVENT_ACCEPTED | ZMQ::EVENT_CLOSED)
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      outbound = context.socket(ZMQ::PUSH)
      outbound.connect("tcp://127.0.0.1:9000").should == nil

      outbound.send("hello world!").should == true
      data = inbound.recv()
      data.should == "hello world!"

      outbound.close.should == nil
      inbound.close.should == nil

      data = monitor.recv()
      data.should == ZMQ::EVENT_ACCEPTED
      data = monitor.recv()
      data.should == ZMQ::EVENT_CLOSED
      monitor.close.should == nil
    end

    it "can receive both data and socket events simultaneously" do
      # This is a test to see if we can monitor both ends of the connection
      # simultaneously (via a poll loop) to be sure order of events doesn't matter.
      # We're also testing ZMQ::DONTWAIT for recv here
      inbound = context.socket(ZMQ::PULL)
      monitor = inbound.monitor()
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      outbound = context.socket(ZMQ::PUSH)
      outbound.connect("tcp://127.0.0.1:9000").should == nil

      outbound.send("hello world!").should == true
      outbound.send("is anyone there?").should == true
      outbound.send("goodbye, cruel world!").should == true

      inbound_seq = 0;
      monitor_seq = 0;
      loop do
        # Because inbound/outbound close first, don't recv after close; in general
        # these events will come in order on the respective sockets, but will
        # otherwise be interspersed
        if (inbound_seq < 3)
          data = inbound.recv(ZMQ::DONTWAIT)
          if (data)
            if (inbound_seq == 0)
              data.should == "hello world!"
            elsif (inbound_seq == 1)
              data.should == "is anyone there?"
            elsif (inbound_seq == 2)
              data.should == "goodbye, cruel world!"
              outbound.close.should == nil
              inbound.close.should == nil
            end
            inbound_seq += 1
          end
        end
        data = monitor.recv(ZMQ::DONTWAIT)
        if (data)
          if (monitor_seq == 0)
            data.should == ZMQ::EVENT_LISTENING
          elsif (monitor_seq == 1)
            data.should == ZMQ::EVENT_ACCEPTED
          elsif (monitor_seq == 2)
            data.should == ZMQ::EVENT_CLOSED
            # We're done here; nothing else can be received:
            break;
          end
          monitor_seq += 1
        end
      end
      monitor.close.should == nil      
    end # it can receive both data and socket events simultaneously

    it "can receive both data and socket events simultaneously with select" do
      # This is a test to see if we can monitor both ends of the connection
      # simultaneously (via select) to be sure order of events doesn't matter.      
      # We're obviously also testing ZMQ.select here
      inbound = context.socket(ZMQ::PULL)
      monitor = inbound.monitor()
      inbound.bind("tcp://127.0.0.1:9000").should == nil

      outbound = context.socket(ZMQ::PUSH)
      outbound.connect("tcp://127.0.0.1:9000").should == nil

      outbound.send("hello world!").should == true
      outbound.send("is anyone there?").should == true
      outbound.send("goodbye, cruel world!").should == true

      inbound_seq = 0;
      monitor_seq = 0;
      loop do
        # Because inbound/outbound close first, don't recv after close; in general
        # these events will come in order on the respective sockets, but will
        # otherwise be interspersed
        if (inbound_seq < 3)
          # We're discarding write and error data; shouldn't actually ever receive
          # any in the first place
          data, write, error = ZMQ.select([monitor, inbound])
        else
          data, write, error = ZMQ.select([monitor])
        end
        if (data.length > 1 || data[0] == inbound)
          data = inbound.recv()
          if (data)
            if (inbound_seq == 0)
              data.should == "hello world!"
            elsif (inbound_seq == 1)
              data.should == "is anyone there?"
            elsif (inbound_seq == 2)
              data.should == "goodbye, cruel world!"
              outbound.close.should == nil
              inbound.close.should == nil
            end
            inbound_seq += 1
          end
        end
        if (data[0] == monitor)
          data = monitor.recv()
          if (data)
            if (monitor_seq == 0)
              data.should == ZMQ::EVENT_LISTENING
            elsif (monitor_seq == 1)
              data.should == ZMQ::EVENT_ACCEPTED
            elsif (monitor_seq == 2)
              data.should == ZMQ::EVENT_CLOSED
              # We're done here; nothing else can be received:
              break;
            end
            monitor_seq += 1
          end
        end
      end
      monitor.close.should == nil      
    end # it can receive both data and socket events simultaneously with select
  end # context monitor tests
end # describe rbzmq tests
