#!/bin/bash

# Compiling scala file
scalac -cp tpdejavu.jar output/TraceMonitor.scala 2>&1 -d TraceMonitor.jar
# Updating jar file 
jar -uvfe TraceMonitor.jar TraceMonitor.class