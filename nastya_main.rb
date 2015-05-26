load "./gpss_interpreter.rb"
require "byebug"

GPSS.create_simulation(timer: 4800) do
  function name: "FTYPE" do
    val = rand
    if val < 0.22
      2
    elsif val < 0.55
      1
    else
      3
    end
  end
  generate type: "exponential", name: 1, mean: 106
  priority{ function_call("FTYPE") }
  queue name: "Qu"
  queue name: lambda{ |transact|
    transact.priority
  }
  seize name: "KASSA"
  depart name: "Qu"
  depart name: lambda{ |transact|
    transact.priority
  }
  advance type: "exponential", name: 2, mean: 96
  release name: "KASSA"
end

# FTYPE FUNCTION RN1,D3
# .22,2/.55,1/1,3
# 1.  GENERATE (EXPONENTIAL(1,0,106))
# 2.  ASSIGN TYPE,FN$FTYPE
# 3.  PRIORITY P$TYPE
# 4.  QUEUE Qu
# 5.  QUEUE P$TYPE
# 6.  SEIZE KASSA
# 7.  DEPART Qu
# 8.  DEPART P$TYPE
# 9.  ADVANCE (EXPONENTIAL(1,0,96))
# 10. RELEASE KASSA
# 11. TERMINATE
# 12. GENERATE 4800
# 13. TERMINATE 1
# 14. START 1
