Properties Compilation
======================

## Automated Compilation Script

A new compilation script `compile_properties.sh` has been created to automate the entire compilation process for properties. This script streamlines all the manual steps described below into a single command.

### Usage

1. **Copy the script**: Place `compile_properties.sh` in the same directory as your `prop.qtl` and `spec.pqtl` files
2. **Make it executable**: `chmod +x compile_properties.sh`
3. **Run the script**: `./compile_properties.sh <package_name>`

**Example:**
```bash
./compile_properties.sh speed_limit
```

The script will automatically:
- Generate the TraceMonitor.scala file
- Apply all necessary modifications (package declaration, function updates)
- Compile the Scala code and create the JAR file
- Generate a Python test script (`test_<package_name>.py`)

---

## Manual Compilation Process

If you prefer to compile manually or need to understand the individual steps, follow the documentation below.

Refer to the following documentation for installation:
https://teal-ice-1dd.notion.site/Dejavu-a2c67c25839b4dff9de9b8503fe7dc7b?pvs=4




1. Place `tpdejavu.jar` in the same directory as the property files

2. run the following command: This generates the TraceMonitor.scala based on the written `prop` and `spec` files
```bash
java -cp tpdejavu.jar dejavu.Verify --specfile prop.qtl --prefile spec.pqtl --execution 1
```
    
3. Update the `TraceMonitor.scala`
    1. Add package to the beginning to run multiple properties simultaneously 
        
        ```scala
        package package_name // At the beginning of the file
        ```
        
    2. Update the following functions 
        
        ```scala
          def submit(name: String, args: List[Any]): Boolean = {
            if (Options.STATISTICS) {
              statistics.update(name)
            }
            state.update(name, args)
            return evaluate()
          }
        ```
        
        ```scala
          def evaluate(): Boolean = {
            debug(s"\ncurrentTime = $currentTime\n$state\n")
            for (formula <- formulae) {
              formula.setTime(deltaTime)
              if (!formula.evaluate()) {
                errors += 1
                println(s"\n*** Property ${formula.name} violated on event number $lineNr:\n")
                println(state)
                return false;
              }
            }
        
            return true;
          }
        ```
        
        ```scala
        object TraceMonitor {
        
          var moni_ = new PropertyMonitor( PreMonitor )
        
          def eval(event: String): Boolean = {
        
            //println("MONITOR RECEIVED: ", event)
            openResultFile("dejavu-results")
            var input = event.split(",")
            var name = input(0)
            var args = new ListBuffer[Any]()
            Options.BITS = 20       
            moni_.setTime(moni_.lineNr) //comment if untimed
            for (i <- 1 until input.length) {
                  args += input(i)
              
            }
            moni_.lineNr+=1
            //println("arguments:", args.toList)
          //  var res =  moni_.submit(name, args)
          var res = false
            if(Options.PRE_PREDICTION){
            val modifiedEvent = PreMonitor.evaluate(name,args: _*)
            modifiedEvent match {
              case Some(first :: second :: _) =>
                res = moni_.submit(first.toString, second.asInstanceOf[List[String]])
              case Some(event_name: String) =>
                if (event_name != "skip") res = moni_.submit(event_name.toString, Nil)
              case Some(_) =>
                println("Unexpected event structure output from the pre processing")
              case None =>
                res = moni_.submit(name, args.toList)
            }
            }
        
            //println("%d",moni_.lineNr)
            closeResultFile()
            // println("RESULT:");
            // println(res);
            return res;
          }
        
          def main(args: Array[String]): Unit = {
            if (1 <= args.length && args.length <= 3) {
              if (args.length > 1) Options.BITS = args(1).toInt
              val m = new PropertyMonitor( PreMonitor )
              val file = args(0)
              if (args.length == 3 && args(2) == "debug") Options.DEBUG = true
              if (args.length == 3 && args(2) == "profile") Options.PROFILE = true
              try {
                openResultFile("dejavu-results")
                if (Options.PROFILE) {
                  openProfileFile("dejavu-profile.csv")
                  m.printProfileHeader()
                }
                m.submitCSVFile(file)
              } catch {
                  case e: Throwable =>
                    println(s"\n*** $e\n")
                    // e.printStackTrace()
              } finally {
                closeResultFile()
                if (Options.PROFILE) closeProfileFile()
              }
            } else {
              println("*** call with these arguments:")
              println("<logfile> [<bits> [debug|profile]]")
            }
          }
        }
        ```
        
    
4. Compile the `TraceMonitor.jar` 
```bash
  # Compiling scala file
  scalac -cp tpdejavu.jar output/TraceMonitor.scala 2>&1 -d TraceMonitor.jar
  # Updating jar file 
  jar -uvfe TraceMonitor.jar TraceMonitor.class
```
