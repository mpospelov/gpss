require 'terminal-table'

class GPSS

  attr_accessor :storages, :generators, 
    :queues, :transacts, :devices, :queues_sizes

  class << self

    def create_simulation(timer:, &block)
      gpss = self.new(timer, &block)
      gpss.run
      print_queues(gpss)
      print_storages(gpss)
      print_devices(gpss)
      puts "1"
    end

    def print_queues(gpss)
      averages = Hash[gpss.queues_sizes.map do |name, arr|
        [name, arr.inject(0.0){|sum, el| sum + el}/arr.size]
      end]
      table = Terminal::Table.new title: "Queues", 
        headings: [ "Name", "Max Size", "Average Size"], 
        rows: gpss.queues.map{|name, q| [name, q.max_size, averages[name]] }
      puts table
      puts "\n"
    end

    def print_storages(gpss)
      table = Terminal::Table.new title: "Storages", 
        headings: [ "Name", "Max Stored"], 
        rows: gpss.storages.map{|name, q| [name, q.max_stored] }
      puts table
      puts "\n"
    end

    def print_devices(gpss)
      table = Terminal::Table.new title: "Devices", 
        headings: [ "Name", "Max Size"], 
        rows: gpss.devices.map{|name, q| [name, q.max_size] }
      puts table
      puts "\n"
    end

  end

  def initialize(timer, &block)
    @simulation = Simulation.new
    @timer = timer
    @storages = {}
    @queues = {}
    @queues_sizes = {}
    @devices = {}
    @transacts = []

    @random_generators = {}
    @generators_finishes = {}
    parser = CommandParser.new
    parser.parse(&block)
    @commands = parser.commands
  end

  def run
    transacts_count = @transacts.length
    commands_length = @commands.length
    @transacts << Transact.new(time: 0, command: 0)
    current_time = 0
    while transact = next_transact
      command_number = transact.current_command
      command = @commands[command_number]
      command_name = command[0]
      command_args = command[1]
      command_block = command[2]

      @queues.each do |name, q|
        @queues_sizes[name] ||= []
        @queues_sizes[name] << q.size
      end

      send(command_name, transact, command_number, *command_args, &command_block)
      transact.current_command += 1
    end
  end

  def next_transact
    @transacts.sort_by!(&:current_time)
    result = @transacts.first
    if result.current_command != @commands.length
      result
    end
  end

  def storage(transact, command_number, size:, name:)
    @storages[name] ||= Storage.new(size: size)
  end

  def generate(transact, command_number, attributes)
    name = attributes[:name]
    type = attributes[:type]
    attributes.delete(:type)
    if @generators_finishes[name].nil?
      current_time = 0
      while current_time < @timer
        @random_generators[name] ||= RandomGenerator.send(type, attributes)
        generator = @random_generators[name]
        value = generator.next
        current_time += value
        @transacts << Transact.new(time: current_time, command: command_number)
      end
      @generators_finishes[name] = true
    end
  end

  def queue(transact, command_number, name:)
    @queues[name] ||= Queue.new
    queue = @queues[name]
    queue.enter
  end

  def advance(transact, command_number, attributes)
    type = attributes[:type]
    attributes.delete(:type)
    @random_generators[attributes[:name]] ||= RandomGenerator.send(type, attributes)
    generator = @random_generators[attributes[:name]]
    value = generator.next
    transact.add_time(value)
  end

  def test_condition(transact, command_number, &block)
  end

  def enter(transact, command_number, name:)
    @storages[name].enter
  end

  def depart(transact, command_number, name:)
    @queues[name].depart
  end

  def leave(transact, command_number, name:)
    @storages[name].enter
  end

  def seize(transact, command_number, name:)
    @devices[name] ||= Device.new
    @devices[name].seize(transact)
  end

  def release(transact, command_number, name:)
    @devices[name].release(transact)
  end

  class CommandParser

    attr_accessor :commands

    def initialize
      @commands = []
    end

    def parse(&block)
      instance_eval(&block)
    end

    def method_missing(name, *args, &block)
      @commands << [name, args, block]
    end

  end

  class Device
    attr_accessor :size, :max_size

    def initialize
      @size, @max_size = 0, 0
    end

    def seize(transact)
      @size += 1
      @max_size = @size if @size > @max_size
    end

    def release(transact)
      @size -= 1
    end

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

    attr_accessor :current_time, :live_time, :current_command

    @@max_index = 0

    def initialize(time:, command:)
      @current_command = command
      @live_time = 0
      @index = @@max_index
      @@max_index += 1
      @current_time = time
    end

    def add_time(value)
      @live_time += value
      @current_time += value
    end

    def pass_command?(number)
      @current_command > number
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
