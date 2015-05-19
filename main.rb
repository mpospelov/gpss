load "./gpss_interpreter.rb"
require "byebug"

GPSS.create_simulation(timer: 600000) do
  station1 = storage size: 3, name: "station1"
  generate :normal_distribution, name: 1, mean: 115, std_dev: 30
  line1 = queue name: "line1"
  line1.enter
  station1.enter
  line1.depart
  advance :normal_distribution, name: 1, mean: 335, std_dev: 60
  test{ line1.size < 1 }
  station1.leave
  line2 = queue name: "line2"
  line2.enter
  station2 = storage size: 1, name: "station2"
  station2.enter
  line2.depart
  advance :normal_distribution, name: 1, mean: 115, std_dev: 20
  station2.leave
end


# DEVICES STORAGE 3
# GENERATE (uniform(1,85,145))
# QUEUE LINE1
# ENTER DEVICES
# DEPART LINE1
# ADVANCE (uniform(1,275,395))
# TEST L Q$LINE2,1
# LEAVE DEVICES
# QUEUE LINE2
# SEIZE STATION2
# DEPART LINE2
# ADVANCE (uniform(1,95,135))
# RELEASE STATION2
# TERMINATE
# GENERATE 600000
# TERMINATE 1
# START 1
