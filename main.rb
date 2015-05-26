load "./gpss_interpreter.rb"
require "byebug"

GPSS.create_simulation(timer: 6000) do
  storage size: 3, name: "S1_DEVICES"
  generate type: "normal_distribution", name: 1, mean: 115, std_dev: 30
  queue name: "LINE1"
  enter name: "S1_DEVICES"
  seize name: "STATION1"
  depart name: "LINE1"
  advance type: "normal_distribution", name: 2, mean: 335, std_dev: 60
  test_condition{ get_queue("LINE2").size < 1 }
  release name: "STATION1"
  leave name: "S1_DEVICES"
  queue name: "LINE2"
  seize name: "STATION2"
  depart name: "LINE2"
  advance type: "normal_distribution", name: 3, mean: 115, std_dev: 20
  release name: "STATION2"
end


# DEVICES STORAGE 3
# GENERATE (uniform(1,85,145))
# QUEUE LINE1
# ENTER DEVICES
# SEIZE STATION1
# DEPART LINE1
# ADVANCE (uniform(1,275,395))
# TEST L Q$LINE2,1
# RELEASE STATION1
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
