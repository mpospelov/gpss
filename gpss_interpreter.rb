class GPSS

  attr_accessor :storages, :generators, :queues, :transacts

  class << self

    def create_simulation(timer:, &block)
      gpss = self.new(timer, &block)
      gpss.run
      debugger
    end

  end

  def initialize(timer, &block)
    @timer = timer
    @simulation = Simulation.new
    @simulation.add_future_event([1, timer, nil, 0])

    @storages = {}
    @generators = {}
    @queues = {}
    @transacts = []

    @code = block
  end

  def run
    while current_time < @timer
      instance_eval(&@code)
    end
  end

  def current_time
    oldest_transact = @transacts.max_by(&:current_time)
    if oldest_transact.nil?
      0
    else
      oldest_transact.current_time
    end
  end

  def storage(size:, name:)
    @storages[name] ||= Storage.new(size: size)
  end

  def generate(type, attributes)
    @generators[attributes[:name]] ||= RandomGenerator.send(type, attributes)
    generator = @generators[attributes[:name]]
    value = generator.next + current_time
    @current_transact = Transact.new(time: value)
    @transacts << @current_transact
    @simulation.add_future_event([])
  end

  def queue(name:)
    @queues[name] ||= Queue.new
  end

  def advance(type, attributes)
    @generators[attributes[:name]] ||= RandomGenerator.send(type, attributes)
    generator = @generators[attributes[:name]]
    value = generator.next
    @current_transact.add_time(value)
  end

  def test(&block)
  end


  class Simulation

    attr_accessor :current_events_chain, :future_events_chain

    def initialize
      @current_events_chain, @future_events_chain = [], []
    end

    def add_future_event(event)
      @future_events_chain << event
    end

  end

  class Transact

    attr_accessor :current_time, :live_time

    @@max_index = 0

    def initialize(time:)
      @live_time = 0
      @index = @@max_index
      @@max_index += 1
      @current_time = time
    end

    def add_time(value)
      @live_time += value
      @current_time += value
    end
  end

  class Queue
    attr_accessor :size, :max_size

    def initialize
      @size = 0
      @max_size = 0
    end

    def enter
      @size += 1
      @max_size = @size if @size > @max_size
    end

    def depart
      @size -= 1
    end

  end

  class Storage
    attr_accessor :size, :max_stored

    def initialize(size:)
      @size = size
      @stored = 0
      @max_stored = 0
    end

    def enter
      @stored += 1
      @max_stored = @stored if @stored > @max_stored
    end

    def leave
      @stored -= 1
    end
  end

  class RandomGenerator
    attr_accessor :distribution
    @generators = {}

    class << self
      def normal_distribution(name:, mean:, std_dev:)
        @generators[name] || begin
          build name, RandomGaussian.new(mean, std_dev, Random.new)
        end
      end

      private

        def build(name,distribution)
          generator = self.new(distribution)
          @generators[name] = generator
          generator
        end

    end

    def initialize(distribution)
      @distribution = distribution
    end

    def next
      @distribution.rand
    end

    class RandomGaussian
      def initialize(mean, stddev, random)
        @random = random
        @mean = mean
        @stddev = stddev
        @valid = false
        @next = 0
      end

      def rand
        if @valid then
          @valid = false
          return @next
        else
          @valid = true
          x, y = self.class.gaussian(@mean, @stddev, @random)
          @next = y
          return x
        end
      end

      private

        def self.gaussian(mean, stddev, random)
          theta = 2 * Math::PI * random.rand
          rho = Math.sqrt(-2 * Math.log(1 - random.rand))
          scale = stddev * rho
          x = mean + scale * Math.cos(theta)
          y = mean + scale * Math.sin(theta)
          return x, y
        end

    end

  end

end
