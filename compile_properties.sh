#!/bin/bash

# Color definitions for better visual output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Check if package name argument is provided
if [ $# -ne 1 ]; then
    echo -e "${RED}Usage: $0 <package_name>${NC}"
    echo -e "${YELLOW}Example: $0 speed_limit${NC}"
    exit 1
fi

PACKAGE_NAME=$1

echo -e "${BOLD}${BLUE}🔧 Processing package: ${CYAN}$PACKAGE_NAME${NC}"

# Step 1: Run the commands from create_scala.sh
echo -e "\n${BOLD}${GREEN}📝 Step 1: Running scala generation...${NC}"
java -cp tpdejavu.jar dejavu.Verify --specfile prop.qtl --prefile spec.pqtl --execution 1

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error: Failed to generate scala file${NC}"
    exit 1
fi

echo -e "\n${BOLD}${GREEN}✏️  Step 2: Modifying generated TraceMonitor.scala...${NC}"

# Step 2.1: Add package declaration to the beginning
sed -i "1i package $PACKAGE_NAME\n" output/TraceMonitor.scala

# Step 2.2: Replace the submit function with new implementation
sed -i '/def submit(name: String, args: List\[Any\]): Unit = {/,/^  }$/c\
  def submit(name: String, args: List[Any]): Boolean = {\
    if (Options.STATISTICS) {\
      statistics.update(name)\
    }\
    state.update(name, args)\
    return evaluate()\
  }' output/TraceMonitor.scala

# Step 2.3: Replace the evaluate function with new implementation  
sed -i '/def evaluate(): Unit = {/,/^  }$/c\
  def evaluate(): Boolean = {\
    debug(s"\\ncurrentTime = $currentTime\\n$state\\n")\
    for (formula <- formulae) {\
      formula.setTime(deltaTime)\
      if (!formula.evaluate()) {\
        errors += 1\
        println(s"\\n*** Property ${formula.name} violated on event number $lineNr:\\n")\
        println(state)\
        return false;\
      }\
    }\
\
    return true;\
  }' output/TraceMonitor.scala

# Step 2.4: Replace object TraceMonitor with new implementation
# First, find the line number where object TraceMonitor starts
OBJECT_START=$(grep -n "object TraceMonitor" output/TraceMonitor.scala | cut -d: -f1)

if [ -z "$OBJECT_START" ]; then
    echo "Error: Could not find 'object TraceMonitor' in the file"
    exit 1
fi

# Replace from object TraceMonitor to end of file
sed -i "${OBJECT_START},\$c\\
object TraceMonitor {\\
\\
  var moni_ = new PropertyMonitor( PreMonitor )\\
\\
  def eval(event: String): Boolean = {\\
\\
    //println(\"MONITOR RECEIVED: \", event)\\
    openResultFile(\"dejavu-results\")\\
    var input = event.split(\",\")\\
    var name = input(0)\\
    var args = new ListBuffer[Any]()\\
    Options.BITS = 20       \\
    moni_.setTime(moni_.lineNr) //comment if untimed\\
    for (i <- 1 until input.length) {\\
          args += input(i)\\
      \\
    }\\
    moni_.lineNr+=1\\
    //println(\"arguments:\", args.toList)\\
  //  var res =  moni_.submit(name, args)\\
  var res = false\\
    if(Options.PRE_PREDICTION){\\
    val modifiedEvent = PreMonitor.evaluate(name,args: _*)\\
    modifiedEvent match {\\
      case Some(first :: second :: _) =>\\
        res = moni_.submit(first.toString, second.asInstanceOf[List[String]])\\
      case Some(event_name: String) =>\\
        if (event_name != \"skip\") res = moni_.submit(event_name.toString, Nil)\\
      case Some(_) =>\\
        println(\"Unexpected event structure output from the pre processing\")\\
      case None =>\\
        res = moni_.submit(name, args.toList)\\
    }\\
    }\\
\\
    //println(\"%d\",moni_.lineNr)\\
    closeResultFile()\\
    // println(\"RESULT:\");\\
    // println(res);\\
    return res;\\
  }\\
\\
  def main(args: Array[String]): Unit = {\\
    if (1 <= args.length && args.length <= 3) {\\
      if (args.length > 1) Options.BITS = args(1).toInt\\
      val m = new PropertyMonitor( PreMonitor )\\
      val file = args(0)\\
      if (args.length == 3 && args(2) == \"debug\") Options.DEBUG = true\\
      if (args.length == 3 && args(2) == \"profile\") Options.PROFILE = true\\
      try {\\
        openResultFile(\"dejavu-results\")\\
        if (Options.PROFILE) {\\
          openProfileFile(\"dejavu-profile.csv\")\\
          m.printProfileHeader()\\
        }\\
        m.submitCSVFile(file)\\
      } catch {\\
          case e: Throwable =>\\
            println(s\"\\\\n*** \${e}\\\\n\")\\
            // e.printStackTrace()\\
      } finally {\\
        closeResultFile()\\
        if (Options.PROFILE) closeProfileFile()\\
      }\\
    } else {\\
      println(\"*** call with these arguments:\")\\
      println(\"<logfile> [<bits> [debug|profile]]\")\\
    }\\
  }\\
}" output/TraceMonitor.scala

echo -e "\n${BOLD}${GREEN}🔨 Step 3: Compiling and creating JAR...${NC}"

# Step 3: Run the commands from create_jar.sh
scalac -cp tpdejavu.jar output/TraceMonitor.scala 2>&1 -d TraceMonitor.jar

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error: Failed to compile scala file${NC}"
    exit 1
fi

# Update jar file 
jar -uvfe TraceMonitor.jar TraceMonitor.class

echo -e "\n${BOLD}${GREEN}🐍 Step 4: Creating Python test script...${NC}"

# Step 4: Create Python script with appropriate class name
cat > test_${PACKAGE_NAME}.py << EOF
import jpype
import jpype.imports

import time

jpype.startJVM(jpype.getDefaultJVMPath(), "-Djava.class.path=tpdejavu.jar:TraceMonitor.jar")

monitor = jpype.JClass("${PACKAGE_NAME}.TraceMonitor")

file = open("log.csv")
while True:
    line = file.readline()
    if not line:
        break
    line = line.strip()
    monitor.eval(line)
EOF

echo -e "\n${BOLD}${GREEN}✅ Processing complete!${NC}"
echo -e "${BOLD}${PURPLE}📁 Generated files:${NC}"
echo -e "  ${CYAN}•${NC} Modified output/TraceMonitor.scala with package ${YELLOW}$PACKAGE_NAME${NC}"
echo -e "  ${CYAN}•${NC} TraceMonitor.jar (compiled)"
echo -e "  ${CYAN}•${NC} test_${PACKAGE_NAME}.py (Python test script)"
echo ""
echo -e "${BOLD}${BLUE}🚀 To use the Python script:${NC}"
echo -e "  ${YELLOW}python3 test_${PACKAGE_NAME}.py${NC}" 