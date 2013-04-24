require 'celluloid'
require 'celluloid/io'
require 'childprocess'

$DEBUG = true

module Celluloid
  module Exec
    def self.included(klass)
      klass.send :include, Celluloid
      klass.mailbox_class Mailbox
    end

    class Mailbox < IO::Mailbox
      def initialize
        super Reactor.new
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
      def self.build(*argv)
        new(*argv)
      end

      def initialize(*argv)
        @process = ::ChildProcess.build(*argv)
      end

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

  def initialize
    process = ChildProcess.build("ruby", "-e", "sleep 2")
    process.wait
  end
end

Demo.new