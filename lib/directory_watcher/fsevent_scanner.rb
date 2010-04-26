
begin
  require 'fsevent'
  require 'thread'
  DirectoryWatcher::HAVE_FSEVENT = true
rescue LoadError
  DirectoryWatcher::HAVE_FSEVENT = false
end

if DirectoryWatcher::HAVE_FSEVENT

# The FSEvent scanner is only availabe on Max OS X systems running version
# 10.5 or greater of the OS (Leopard and Snow Leopard). You must install the
# ruby-fsevent gem to use the FSEvent scanner.
#
class DirectoryWatcher::FseventScanner < DirectoryWatcher::Scanner

  # call-seq:
  #    FseventScanner.new { |events| block }
  #
  # Create an FSEvent based scanner that will generate file events and pass
  # those events (as an array) to the given _block_.
  #
  def initialize( *args, &block )
    super(*args, &block)

    @mutex = Mutex.new
    @ready = ConditionVariable.new
    @signal = 0
    @notifier = Notifier.new(@dir, self)
  end

  # Start the scanner thread. If the scanner is already running, this method
  # will return without taking any action.
  #
  def start
    return if running?

    @stop = false
    @thread = Thread.new(self) {|scanner| scanner.__send__ :run_loop}
    Thread.new { @notifier.start }
    self
  end

  # Stop the scanner thread. If the scanner is already stopped, this method
  # will return without taking any action.
  #
  def stop
    return unless running?

    @stop = true
    @notifier.stop
    @mutex.synchronize { @ready.signal }
    @thread.join
    self
  ensure
    @thread = nil
  end

  # Signal the scanner that changes have occurred in the directory being
  # watched. This method is called by the Notifier class when _on_change_ is
  # fired by the operating system.
  #
  def _signal
    @mutex.synchronize {
      @signal += 1
      @ready.signal
    }
  end


private

  # Calling this method will enter the scanner's run loop. The
  # calling thread will not return until the +stop+ method is called.
  #
  # The run loop is responsible for scanning the directory for file changes,
  # and then dispatching events to registered listeners.
  #
  def run_loop
    loop do
      break if @stop
      run_once

      @mutex.synchronize {
        @signal -= 1 if @signal > 0
        next if @signal > 0
        @ready.wait(@mutex)
      }
    end
  end

  # :stopdoc:
  class Notifier < FSEvent
    def initialize( dir, scanner )
      super()
      @scanner = scanner
      watch_directories Array(dir)
    end

    def on_change( directories )
      @scanner._signal
    end
  end
  # :startdoc:

end  # class DirectoryWatcher::FseventScanner
end  # if HAVE_FSEVENT

