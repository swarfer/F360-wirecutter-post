/**
  Copyright (C) 2012-2019 by Autodesk, Inc.
  All rights reserved.

  Grbl post processor configuration.

  $Revision: 42473 905303e8374380273c82d214b32b7e80091ba92e $
  $Date: 2019-09-04 00:46:02 $
  
  FORKID {0A45B7F8-16FA-450B-AB4F-0E1BC1A65FAA}
  
  V0.0.0 : original from Keith Howlette
  V0.0.1 : Swarfer additions: axis picker, helical off
*/
postversion = "V0.0.1";
debugMode = true;
description = "Grbl Foam Cutter";
vendor = "grbl";
vendorUrl = "https://rckeith.co.uk";
legal = "Copyright (C) 2012-2021 by Autodesk, Inc. and Keith Howlett and David the Swarfer";
certificationLevel = 2;
minimumRevision = 24000;

longDescription = "rcKeith Grbl foam cutting - 4 axis hotwire for simple shapes.";

extension = "nc";
setCodePage("ascii");

capabilities = CAPABILITY_JET;
tolerance = spatial(0.01, MM);

minimumChordLength = spatial(0.25, MM);
minimumCircularRadius = spatial(0.5, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = false;
allowedCircularPlanes = 0; // don't allow any circular motion KH

// user-defined properties
properties = {
  axes : 'XYUZ', // axis words to use 
  power : 0,      // power level, percent, 0 outputs no power commads
  powerdelay: 5   // seconds delay after power the wire on
//  writeMachine: true, // write machine
//  showSequenceNumbers: false, // show sequence numbers
//  sequenceNumberStart: 10, // first sequence number
//  sequenceNumberIncrement: 1, // increment for sequence numbers
//  separateWordsWithSpace: true, // specifies that the words should be separated with a white space
  //throughPower: 255, // set the Laser Power for though cutting
  //etchPower: 50, // set the power for etching
  //vaporizePower: 255 // set the power for vaporize
};

// user-defined property definitions
propertyDefinitions = {
   axes : {
      title: "Axis words to use",
      description: "Choose the words that your controller uses",
      group: 0,
      type: "enum", values:[
         {title:"XYUZ Mega/MKS", id:"XYUZ"},
         {title:"XYUV LinuxCNC", id:"XYUV"},
         {title:"XYAZ Mach3", id:"XYAZ"}, // until a Mach3 user tells us which way the axes work, offer both
         {title:"XYZA Mach3", id:"XYZA"}
         ]
     }, 
   power :  {
      title : "Wire power level (%)",
      description : "Power level in percent, 0 prevents power settings in the Gcode.",
      group: 0,
      type: "number"
      },
   powerdelay:   {
      title : "Delay after power on (S)",
      description : "Seconds to delay after powering the wire on",
      group: 0,
      type: "integer"
      }
//  writeMachine: {title:"Write machine", description:"Output the machine settings in the header of the code.", group:0, type:"boolean"},
//  showSequenceNumbers: {title:"Use sequence numbers", description:"Use sequence numbers for each block of outputted code.", group:1, type:"boolean"},
//  sequenceNumberStart: {title:"Start sequence number", description:"The number at which to start the sequence numbers.", group:1, type:"integer"},
//  sequenceNumberIncrement: {title:"Sequence number increment", description:"The amount by which the sequence number is incremented by in each block.", group:1, type:"integer"},
//  separateWordsWithSpace: {title:"Separate words with space", description:"Adds spaces between words if 'yes' is selected.", type:"boolean"},
  //throughPower: {title: "Through power", description: "Sets the laser power used for through cutting.", type: "number"},
  //etchPower: {title:"Etch power", description:"Sets the laser power used for etching.", type:"number"},
  //vaporizePower: {title:"Vaporize power", description:"Sets the laser power used for vaporize cutting.", type:"number"}
};

var gFormat = createFormat({prefix:"G", decimals:0});
var mFormat = createFormat({prefix:"M", decimals:0});

var xyuzFormat = createFormat({decimals:(unit == MM ? 3 : 4)});
var feedFormat = createFormat({decimals:(unit == MM ? 1 : 2)});
var toolFormat = createFormat({decimals:0});
var powerFormat = createFormat({decimals:0});
var secFormat = createFormat({decimals:3, forceDecimal:true}); // seconds - range 0.001-1000

var xOutput = createVariable({prefix:"X"}, xyuzFormat);
var yOutput = createVariable({prefix:"Y"}, xyuzFormat);
var zOutput = createVariable({prefix:"Z"}, xyuzFormat);
var uOutput = createVariable({prefix:"U"}, xyuzFormat);
var vOutput = createVariable({prefix:"V"}, xyuzFormat);
var aOutput = createVariable({prefix:"A"}, xyuzFormat);

var feedOutput = createVariable({prefix:"F"}, feedFormat);
var sOutput = createVariable({prefix:"S", force:true}, powerFormat);
var zlast=0;
var ulast=0;

// circular output
var iOutput = createVariable({prefix:"I"}, xyuzFormat);
var jOutput = createVariable({prefix:"J"}, xyuzFormat);

var gMotionModal = createModal({force:true}, gFormat); // modal group 1 // G0-G3, ...
var gPlaneModal = createModal({onchange:function () {gMotionModal.reset();}}, gFormat); // modal group 2 // G17-19
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91
var gFeedModeModal = createModal({}, gFormat); // modal group 5 // G93-94
var gUnitModal = createModal({}, gFormat); // modal group 6 // G20-21

var WARNING_WORK_OFFSET = 0;

// collected state
var sequenceNumber;
var currentWorkOffset;

var lastfeed = 0;

/**
   Writes the specified block.
*/
function writeBlock()
   {
   writeWords(arguments);
   }

function formatComment(text)
   {
   return "(" + String(text).replace(/[()]/g, "") + ")";
   }

/**
   Output a comment, Wrapping long comments.
*/
function writeComment(text)
   {
   text = String(text).replace( /[^a-zA-Z\d:=,.]+/g, " "); // remove illegal chars
   if (text.length > 70)
      {
      var bits = text.split(" "); // get all the words
      var out = '';
      for (i = 0; i < bits.length; i++)
         {
         out += bits[i] + " ";
         if (out.length > 60)           // a long word on the end can take us to 80 chars!
            {
            writeln("(" + out.trim() + ")");
            out = "";
            }
         }
      if (out.length > 0)
         writeln("(" + out.trim() + ")");
      }
   else
      writeln("(" + text + ")");
   }

/**
   Writes the correct axis words according to the user selection
   */
function writeMove(mode,x,y,u,v)
   {
   if (mode)
      forceXYZ(); // Always output even in value doesn't change from previous line KH Jan 2021
      
   var xo = xOutput.format(x);   
   var yo = yOutput.format(y);   
   var f = '';
   if (lastfeed > 0)
      f = feedOutput.format(lastfeed);

   if (properties.axes == "XYUZ")
      {
      var uo = uOutput.format(u);   
      var vo = zOutput.format(v);
      }      
   if (properties.axes == "XYUV")
      {
      var uo = uOutput.format(u);   
      var vo = vOutput.format(v);
      }      
   if (properties.axes == "XYAZ")
      {
      var uo = aOutput.format(u);   
      var vo = zOutput.format(v);
      }      
   if (properties.axes == "XYZA")
      {
      var uo = zOutput.format(u);   
      var vo = aOutput.format(v);
      }      
   if (xo || yo)   
      writeBlock(gFormat.format(mode), xo,yo,uo,vo,f);
   //writeComment(properties.axes);
   }   

function getPowerMode(section)
   {
   var mode;
   switch (section.quality)
      {
      case 0: // auto
         mode = 4;
         break;
      case 1: // high
         mode = 3;
         break;
      /*
         case 2: // medium
         case 3: // low
      */
      default:
         error(localize("Only Cutting Mode Through-auto and Through-high are supported."));
         return 0;
      }
   return mode;
   }

function onOpen()
   {

   writeComment("rcKeith did this you have been warned");
   writeComment("the Swarfer added to it you have been warned again");
   writeComment("GRBL 5x hotwire post " + postversion);

   if (programName)
      {
      writeComment("Program " + programName);
      }
   if (programComment)
      {
      writeComment("Comment " + programComment);
      }
   writeComment("You have chosen Axis config " + properties.axes);   

   // dump machine configuration
   var vendor = machineConfiguration.getVendor();
   var model = machineConfiguration.getModel();
   var description = machineConfiguration.getDescription();

   if (vendor || model || description)
      {
      writeComment(localize("Machine"));
      if (vendor)
         {
         writeComment("  " + localize("vendor") + ": " + vendor);
         }
      if (model)
         {
         writeComment("  " + localize("model") + ": " + model);
         }
      if (description)
         {
         writeComment("  " + localize("description") + ": "  + description);
         }
      }

   if ((getNumberOfSections() > 0) && (getSection(0).workOffset == 0))
      {
      for (var i = 0; i < getNumberOfSections(); ++i)
         {
         if (getSection(i).workOffset > 0)
            {
            error(localize("Using multiple work offsets is not possible if the initial work offset is 0."));
            return;
            }
         }

      }

   // absolute coordinates and feed per min
   writeBlock(gAbsIncModal.format(90), gFeedModeModal.format(94), gPlaneModal.format(17));

   switch (unit)
      {
      case IN:
         writeBlock(gUnitModal.format(20));
         break;
      case MM:
         writeBlock(gUnitModal.format(21));
         break;
      }
   writeComment("Start at zero");
   goToZero();
   }

function onComment(message)
   {
   writeComment(message);
   }

/** Force output of X, Y,Z and U . */
function forceXYZ()
   {
   xOutput.reset();
   yOutput.reset();
   zOutput.reset();
   uOutput.reset();
   vOutput.reset();
   aOutput.reset();
   }

/** Force output of X, Y, Z, and F on next output. */
function forceAny()
   {
   forceXYZ();
   feedOutput.reset();
   }

function onSection()
   {

   writeln("");

   if (hasParameter("operation-comment"))
      {
      var comment = getParameter("operation-comment");
      if (comment)
         {
         writeComment(comment);
         }
      }

   if (currentSection.getType() == TYPE_JET) 
      {
      switch (tool.type) 
         {
         case TOOL_LASER_CUTTER:
            break;
         default:
            error(localize("The CNC does not support the required tool/process. Only laser cutting is supported."));
            return;
         }
      }
   /*
      var power = 0;
      switch (currentSection.jetMode) {
      case JET_MODE_THROUGH:
       power = properties.throughPower;
       break;
      case JET_MODE_ETCHING:
       power = properties.etchPower;
       break;
      case JET_MODE_VAPORIZE:
       power = properties.vaporizePower;
       break;
      default:
       error(localize("Unsupported cutting mode."));
       return;
      }
      } else {
      error(localize("The CNC does not support the required tool/process. Only laser cutting is supported."));
      return;
      }
   */
   /*
      // wcs
      var workOffset = currentSection.workOffset;
      if (workOffset == 0) {
      warningOnce(localize("Work offset has not been specified. Using G54 as WCS."), WARNING_WORK_OFFSET);
      workOffset = 1;
      }
      if (workOffset > 0) {
      if (workOffset > 6) {
       error(localize("Work offset out of range."));
       return;
      } else {
       if (workOffset != currentWorkOffset) {
         writeBlock(gFormat.format(53 + workOffset)); // G54->G59
         currentWorkOffset = workOffset;
       }
      }
      }
   */
   //Start at with wire at zero on all axis
   //writeBlock(gFormat.format(0))


      {
      // pure 3D
      var remaining = currentSection.workPlane;
      if (!isSameDirection(remaining.forward, new Vector(0, 0, 1)))
         {
         error(localize("Tool orientation is not supported."));
         return;
         }
      setRotation(remaining);
      }
      
   if (properties.power > 0)
      {
      // turn wire on before moving to section start   
      var p = properties.power / 100.0 * 1000.0;
      writeBlock(mFormat.format(3), sOutput.format(p));
      onDwell(properties.powerdelay);
      }

   var initialPosition = getFramePosition(currentSection.getInitialPosition());
   // check that setup has WCS set correctly at bottom left corner
   if (initialPosition.x < 0)
      {
      writeComment("WARNING: Setup must have WCS in bottom left corner of stock, ie NO negative X moves");
      }
   //writeBlock(gMotionModal.format(0), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y), uOutput.format(initialPosition.x),zOutput.format(initialPosition.y));
   writeMove(0,initialPosition.x, initialPosition.y, initialPosition.x,initialPosition.y);
   }

function onDwell(seconds)
   {
   if (seconds > 99999.999)
      {
      warning(localize("Dwelling time is out of range."));
      }
   seconds = clamp(0.001, seconds, 99999.999);
   writeBlock(gFormat.format(4), "P" + secFormat.format(seconds));
   }


function onRadiusCompensation()
   {
   //pendingRadiusCompensation = radiusCompensation;
   }

function onPower(power)
   {
   //writeComment("onpower " + power);   
   
   }

function onRapid(_x, _y, _z)
   {
   writeMove(0, _x, _y, _x, _y);
   feedOutput.reset();
   }

function onLinear(_x, _y, _z, feed)
   {
   lastfeed = feed;
   writeMove(1, _x, _y, _x, _y);
   }

function onRapid5D(_x, _y, _z, _a, _b, _c)
   {
   error(localize("The CNC does not support 5-axis simultaneous toolpath."));
   }

function onLinear5D(_x, _y, _z, _a, _b, _c, feed)
   {
   error(localize("The CNC does not support 5-axis simultaneous toolpath."));
   }

function forceCircular(plane)
   {
   switch (plane)
      {
      case PLANE_XY:
         xOutput.reset();
         yOutput.reset();
         uOutput.reset();
         zOutput.reset();
         iOutput.reset();
         jOutput.reset();
         break;
      case PLANE_ZX:
         zOutput.reset();
         xOutput.reset();
         uOutput.reset();
         zOutput.reset();
         kOutput.reset();
         iOutput.reset();
         break;
      case PLANE_YZ:
         yOutput.reset();
         zOutput.reset();
         uOutput.reset();
         zOutput.reset();
         jOutput.reset();
         kOutput.reset();
         break;
      }
   }

function onCircular(clockwise, cx, cy, cz, x, y, z, feed)
   {
   linearize(tolerance);
   }

var mapCommand =
   {
   COMMAND_STOP:0,
   COMMAND_END:2
   };

function onCommand(command)
   {
   switch (command)
      {
      case COMMAND_POWER_ON:
         return;
      case COMMAND_POWER_OFF:
         return;
      case COMMAND_LOCK_MULTI_AXIS:
         return;
      case COMMAND_UNLOCK_MULTI_AXIS:
         return;
      case COMMAND_BREAK_CONTROL:
         return;
      case COMMAND_TOOL_MEASURE:
         return;
      }

   var stringId = getCommandStringId(command);
   var mcode = mapCommand[stringId];
   if (mcode != undefined)
      {
      writeBlock(mFormat.format(mcode));
      }
   else
      {
      onUnsupportedCommand(command);
      }
   }

function onSectionEnd()
   {
   forceAny();
   }

function onClose()
   {
   xuToZero()
   if (properties.power > 0)
      {
      writeBlock(mFormat.format(5));
      }   
   //writeBlock(gMotionModal.format(1), sOutput.format(0)); // laser off
   writeBlock(mFormat.format(30)); // stop program, spindle stop, coolant off - required by most controllers
   //writeln("%"); KH
   }

/**
   move to 0 position   
*/   
function goToZero()
   {
   writeMove(0, 0, 0, 0, 0);
   }

/**
   exit the shape to the start position
*/
function xuToZero()
   {
   var pos = getCurrentPosition();
   //var x = xOutput.format(0);
   //var u = uOutput.format(0);
   //var y = yOutput.format(pos.y);
   //var z = zOutput.format(pos.y);
   //writeBlock(gMotionModal.format(0), x, y, u, z );
   writeMove(0,0,pos.y,0,pos.y);
   }