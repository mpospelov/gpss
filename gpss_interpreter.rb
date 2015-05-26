require 'terminal-table'

class GPSS

  attr_accessor :storages, :generators, :functions,
    :queues, :transacts, :devices, :queues_sizes

  class << self

    def create_simulation(timer:, debug: false, &block)
      @@debug = debug || false
      gpss = self.new(timer, &block)
      gpss.run
      print_queues(gpss)
      print_storages(gpss)
      print_devices(gpss)
      print_transacts(gpss)
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

    def print_transacts(gpss)
      active_transacts = gpss.transacts.select{|t| t.live_time != 0 }
      avg = active_transacts.inject(0){|s, t| s+=t.live_time }/active_transacts.count
      max = active_transacts.max_by(&:live_time).live_time
      min = active_transacts.min_by(&:live_time).live_time
      table = Terminal::Table.new title: "Transacts(Active Count: #{active_transacts.count})",
        headings: [ "Average Live Time", "Max Live Time", "Min Live Time"],
        rows: [[avg.round(2), max.round(2), min.round(2)]]
      puts table
      puts "\n"
    end

  end

  def initialize(timer, &block)
    @timer = timer
    @storages = {}
    @queues = {}
    @queues_sizes = {}
    @devices = {}
    @transacts = []
    @functions = {}

    @random_generators = {}
    @generators_finishes = {}
    parser = CommandParser.new(self)
    parser.parse(&block)
    @commands = parser.commands
    @commands_count = @commands.length
  end


  def print_transacts_progress
    puts "Command Num\t|\tCommand Name\t|\tQueue"
    @commands.each_with_index do |command,num|
      transacts_count = @transacts.select{|t| t.current_command - 1 == num }.count
      puts "#{num}.\t#{command[0]}:\t#{"."*transacts_count}"
    end
    puts "_________"
  end

  def run
    transacts_count = @transacts.length
    commands_length = @commands.length
    @transacts << Transact.new(
      time: 0,
      command: 0,
      commands_count: @commands_count)

    while transact = next_transact
      command_number = transact.current_command
      command = @commands[command_number]

      @queues.each do |name, q|
        @queues_sizes[name] ||= []
        @queues_sizes[name] << q.size
      end
      exec(transact)
      transact.current_command += 1
    end
  end

  def exec(transact)
    if @@debug
      pp transact
      puts "\n"
      print_transacts_progress
      sleep 0.1
    end

    command_number = transact.current_command
    command = @commands[command_number]
    command_name = command[0]
    command_args = command[1]
    command_block = command[2]

    send(command_name, transact, command_number, *command_args, &command_block)
  end

  def function(transact, command_number, name:, &block)
    @functions[name] ||= block
  end

  def next_transact
    select_from = @transacts.select(&:not_finished?).
                             sort_by(&:current_time).
                             sort_by(&:priority)
    result = select_from.detect(&:not_blocked?)
    if !result.nil?
      select_from.each do |transact|
        transact.current_time = result.current_time if transact.blocked?
      end
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
        @transacts << Transact.new(time: current_time,
          command: command_number + 1,
          commands_count: @commands_count)
      end
      @generators_finishes[name] = true
    end
  end

  def priority(transact, command_number, &block)
    transact.priority = block.call
  end

  def queue(transact, command_number, name:)
    name = name.call(transact) if name.is_a?(Proc)
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
    transact.add_blocker(block)
  end

  def enter(transact, command_number, name:)
    storage = @storages[name]
    if storage.full?
      transact.current_command -= 1
      blocker = lambda{ !@storages[name].full? }
      transact.add_blocker(blocker)
    else
      storage.enter
    end
  end

  def depart(transact, command_number, name:)
    name = name.call(transact) if name.is_a?(Proc)
    @queues[name].depart
  end

  def leave(transact, command_number, name:)
    @storages[name].leave
  end

  def seize(transact, command_number, name:)
    @devices[name] ||= Device.new
    device = @devices[name]
    if device.work?
      transact.current_command -= 1
      blocker = lambda{ !@devices[name].work? }
      transact.add_blocker(blocker)
    else
      device.seize
    end
  end

  def release(transact, command_number, name:)
    @devices[name].release
  end

  class CommandParser

    attr_accessor :commands

    def initialize(gpss)
      @commands = []
      @gpss = gpss
    end

    def parse(&block)
      instance_eval(&block)
    end

    # RUNTIME METHODS
    def get_queue(name)
      @gpss.queues[name] || Queue.new
    end

    def function_call(name)
      @gpss.functions[name].call
    end

    def method_missing(name, *args, &block)
      @commands << [name, args, block]
    end

  end

  class Device
    attr_accessor :size, :max_size, :is_working

    def seize
      @is_working = true
    end

    def release
      @is_working = false
    end

    def work?
      @is_working
    end

  end

  class Transact

    attr_accessor :start_time, :live_time, :priority,
      :current_command, :commands_count, :index

    @@max_index = 0

    def initialize(time:, command:, commands_count:)
      @priority = 0
      @commands_count = commands_count
      @current_command = command
      @live_time = 0
      @index = @@max_index
      @@max_index += 1
      @start_time = time
      @blockers = []
    end

    def add_time(value)
      @live_time += value
    end

    def add_blocker(proc)
      @blocked_at = current_time
      @blockers << proc
    end

    def finished?
      @current_command >= @commands_count
    end

    def not_finished?
      !finished?
    end

    def pass_command?(number)
      @current_command > number
    end

    def current_time
      @live_time + @start_time
    end

    def current_time=(value)
      new_value = value - @start_time
      @live_time = new_value if new_value > @live_time
    end

    def blocked?
      blocker = @blockers.detect{|b| !b.call}
      if blocker.nil? # no active blocker
        @blockers = []
        false
      else
        true
      end
    end

    def not_blocked?
      !blocked?
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

    def full?
      @size == @stored
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

      def exponential(name:, mean:)
        @generators[name] || begin
          build name, RandomExpo.new(mean, Random.new)
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

    class RandomExpo
      def initialize(mean, random)
        @mean = mean
        @random = random
      end

      def rand
        -@mean * Math.log(@random.rand) if @mean > 0
      end

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
