require 'celluloid'
require 'childprocess'

$DEBUG = true

module Celluloid
  module Exec
    def self.included(klass)
      klass.send :include, Celluloid
      klass.mailbox_class Mailbox
    end

    class Mailbox < EventedMailbox
      def initialize
        super Reactor
      end
    end

    class Reactor
      Monitor = Struct.new(:task, :process, :set)

      def initialize
        @monitors = []
      end

      def register(process, set)
        @monitors << Monitor.new(Task.current, process, set)
        Task.suspend :execwait
      end

      def wakeup
        Logger.info "wakeup for #{inspect}"
      end

      def shutdown
        Logger.info "shutdown for #{inspect}"
      end

      def run_once(timeout = nil)
        Logger.info "finding a process which is ready: #{@monitors.inspect}"
        @monitors.each do |monitor|
          process = monitor.process
          case monitor.set
          when :wait
            if exited?(process, timeout || 0.1)
              @monitors.delete(monitor)
              monitor.task.resume
            end
          else
            raise "unknown set: #{monitor.inspect}"
          end
        end
      end

      def exited?(process, timeout)
        process.poll_for_exit(timeout)
        true
      rescue ::ChildProcess::TimeoutError
        false
      end
    end

    class ChildProcess
      extend Forwardable

      def self.build(*argv)
        new(*argv)
      end

      def initialize(*argv)
        @process = ::ChildProcess.build(*argv)
      end

      def_delegators :@process, :io, :duplex, :duplex=

      def evented?
        actor = Thread.current[:celluloid_actor]
        actor && actor.mailbox.is_a?(Mailbox)
      end

      def start
        @process.start
      end

      def wait
        if evented?
          actor = Thread.current[:celluloid_actor]
          actor.mailbox.reactor.register(@process, :wait)
        else
          @process.wait
        end
      end
    end
  end
end

class Demo
  include Celluloid::Exec
  include Celluloid::Logger

  def initialize
    @sleeper = ChildProcess.build("ruby", "-e", "sleep 2")
    @linereader = ChildProcess.build("ruby", "-e", "p $stdin.gets")
  end

  def run
    @sleeper.start
    @sleeper.wait

    out      = Tempfile.new("duplex")
    out.sync = true

    @linereader.io.stdout = @linereader.io.stderr = out
    @linereader.duplex = true
    @linereader.start

    info "-> puts"
    @linereader.io.stdin.puts "hello world"
    info "-> close"
    @linereader.io.stdin.close
    info "-> wait"
    @linereader.wait

    info "-> rewind"
    out.rewind
    info "-> readpartial"
    begin
      loop {
        data = out.readpartial(8192)
        info "data: #{data.inspect}"
      }
    rescue EOFError
    end

    info "done"
  end
end

Demo.new.run
