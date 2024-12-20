//
// Copyright 2016-2021 by Garmin Ltd. or its subsidiaries.
// Subject to Garmin SDK License Agreement and Wearables
// Application Developer Agreement.
//

import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
using Toybox.Timer;
using Toybox.Graphics as Gfx;
using Toybox.Lang as Lang;
using Toybox.Math as Math;
using Toybox.Time.Gregorian as Calendar;
using Toybox.WatchUi as Ui;
using Toybox.Application as App;
import Toybox.Application.Storage;
import Toybox.ActivityMonitor;
using Toybox.System as Sys;

//! This implements an analog watch face
//! Original design by Austen Harbour
class AnalogView extends WatchUi.WatchFace {
    private var _font as FontResource?;
    private var _isAwake as Boolean?;
    private var _screenShape as ScreenShape;
    private var _dndIcon as BitmapResource?;
    private var _offscreenBuffer as BufferedBitmap?;
    private var _hashMarksBuffer as BufferedBitmap?;
    private var _screenCenterPoint as Array<Number>?;
    private var _fullScreenRefresh as Boolean;
    private var _hashMarksDrawn as Boolean;
    private var _partialUpdatesAllowed as Boolean;
    private var _secondHandCounter as Number;

    var showSecond = true;
    var background_color = Gfx.COLOR_BLACK;
    var sec_color = Gfx.COLOR_WHITE;
    var width_screen, height_screen, min_screen;
    var sec_length;
    var sec_width;
    var sec_width_clipbox;

    var hashMarksArray = new [24];

    var batt_width_rect = 12;
    var batt_height_rect = 6;
    var batt_width_rect_small = 2;
    var batt_height_rect_small = 4;
    var batt_x, batt_y, batt_x_small, batt_y_small;

    var dmd_w4;
    var dmd_yy, dmd_x;
    var dmd_w;
    var dmd_h;

    //! Initialize variables for this view
    public function initialize() {
        //System.println("5B");
        WatchFace.initialize();
        var settings = Sys.getDeviceSettings();
        _screenShape = System.getDeviceSettings().screenShape;
        _fullScreenRefresh = true;
        _hashMarksDrawn = false;
        _partialUpdatesAllowed = (WatchUi.WatchFace has :onPartialUpdate);
        _secondHandCounter = 0;
        _isAwake = true;
        readStorageValues();
        //System.println("5B");
    }

    //! Configure the layout of the watchface for this device
    //! @param dc Device context
    public function onLayout(dc as Dc) as Void {
        //System.println("1");
        // Load the custom font we use for drawing the 3, 6, 9, and 12 on the watchface.
        _font = WatchUi.loadResource($.Rez.Fonts.id_font_black_diamond) as FontResource;

        // If this device supports the Do Not Disturb feature,
        // load the associated Icon into memory.
        if (System.getDeviceSettings() has :doNotDisturb) {
            _dndIcon = WatchUi.loadResource($.Rez.Drawables.DoNotDisturbIcon) as BitmapResource;
        } else {
            _dndIcon = null;
        }

        var offscreenBufferOptions = {
                :width=>dc.getWidth(),
                :height=>dc.getHeight(),
                :palette=> [
                    //Graphics.COLOR_DK_GRAY,
                    //Graphics.COLOR_LT_GRAY,
                    Graphics.COLOR_BLACK,
                    Graphics.COLOR_WHITE
                ]
            };
        //System.println("2");
        var hashMarksBufferOptions ={
                :width=>dc.getWidth(),
                :height=>dc.getHeight(),
                :palette=> [
                    //Graphics.COLOR_DK_GRAY,
                    //Graphics.COLOR_LT_GRAY,
                    Graphics.COLOR_BLACK,
                    Graphics.COLOR_WHITE
                ]
            };

        if (Graphics has :createBufferedBitmap) {
            // get() used to return resource as Graphics.BufferedBitmap
            _offscreenBuffer = Graphics.createBufferedBitmap(offscreenBufferOptions).get() as BufferedBitmap;

            _hashMarksBuffer = Graphics.createBufferedBitmap(hashMarksBufferOptions).get() as BufferedBitmap;
        } else if (Graphics has :BufferedBitmap) { // If this device supports BufferedBitmap, allocate the buffers we use for drawing
            // Allocate a full screen size buffer with a palette of only 4 colors to draw
            // the background image of the watchface.  This is used to facilitate blanking
            // the second hand during partial updates of the display
            _offscreenBuffer = new Graphics.BufferedBitmap(offscreenBufferOptions);

            // Allocate a buffer tall enough to draw the date into the full width of the
            // screen. This buffer is also used for blanking the second hand. This full
            // color buffer is needed because anti-aliased fonts cannot be drawn into
            // a buffer with a reduced color palette
            _hashMarksBuffer = new Graphics.BufferedBitmap(hashMarksBufferOptions);
        } else {
            _offscreenBuffer = null;
            _hashMarksBuffer = null;
        }
        //System.println("3");

        _screenCenterPoint = [dc.getWidth() / 2, dc.getHeight() / 2];
                //get screen dimensions
        width_screen = dc.getWidth();
        if (width_screen < 175) { width_screen -=8; } //Instinct S adjustment bec. the right edge of the bezel ends a bit before the actual right screen edge
        height_screen = dc.getHeight();
        min_screen = ( width_screen<height_screen ) ? width_screen : height_screen;
        var hm_factor = -1.08;
        if (width_screen < 175) { hm_factor = -1.1; } //Instinct S adjustment

        //get hash marks position
        for(var i = 0; i < 12; i+=1)
        {
            hashMarksArray[i] = new [2];
            //if(i != 0 && i != 6 && i != 12 && i != 18)
            {
                hashMarksArray[i][0] = (i / 12.0) * Math.PI * 2;
                hashMarksArray[i][1] = hm_factor*min_screen/2;
            }
        }

        //get battery icon position
        batt_x = (width_screen/2) - (batt_width_rect/2) - (batt_width_rect_small/2);
        batt_y = (height_screen* .77) - (batt_height_rect/2);
        batt_x_small = batt_x + batt_width_rect;
        batt_y_small = batt_y + ((batt_height_rect - batt_height_rect_small) / 2);

        //Figure Move Dot positions
        dmd_w4 =Math.ceil((batt_width_rect + batt_width_rect_small+3)/4);
        dmd_yy = batt_y + 1.5 * batt_height_rect;
        dmd_w = Math.ceil((batt_width_rect + batt_width_rect_small+3)/4-1);
        dmd_h = batt_height_rect-3;
        dmd_x = batt_x + (batt_width_rect + batt_width_rect_small - (4 * dmd_w4 -1))/2; //center the move dots under the battery.  If possible.

        sec_length = width_screen*.43; //this will be change @ runtime per Storage.getValue("Long Second"), see below.
        //sec_length = width_screen*.23;
        sec_width = 2;
        sec_width_clipbox = sec_width+1;

        setLayout(Rez.Layouts.WatchFace(dc));
    }

    //! This function is used to generate the coordinates of the 4 corners of the polygon
    //! used to draw a watch hand. The coordinates are generated with specified length,
    //! tail length, and width and rotated around the center point at the provided angle.
    //! 0 degrees is at the 12 o'clock position, and increases in the clockwise direction.
    //! @param centerPoint The center of the clock
    //! @param angle Angle of the hand in radians
    //! @param handLength The length of the hand from the center to point
    //! @param tailLength The length of the tail of the hand
    //! @param width The width of the watch hand
    //! @return The coordinates of the watch hand
    private function generateHandCoordinates(centerPoint as Array<Number>, angle as Float, handLength as Number, tailLength as Number, width as Number) as Array<[Numeric, Numeric]> {
        // Map out the coordinates of the watch hand
        var coords = [[-(width / 2), tailLength],
                      [-(width / 2), -handLength],
                      [width / 2, -handLength],
                      [width / 2, tailLength]];
        var result = new Array<[Numeric, Numeric]>[4];
        var cos = Math.cos(angle);
        var sin = Math.sin(angle);

        // Transform the coordinates
        for (var i = 0; i < 4; i++) {
            var x = (coords[i][0] * cos) - (coords[i][1] * sin) + 0.5;
            var y = (coords[i][0] * sin) + (coords[i][1] * cos) + 0.5;

            result[i] = [centerPoint[0] + x, centerPoint[1] + y];
        }

        return result;
    }

    //! Draws the clock tick marks around the outside edges of the screen.
    //! @param dc Device context
    private function drawHashMarksOld(dc as Dc) as Void {
        return;
        /*
        var width = dc.getWidth();
        var height = dc.getHeight();

        // Draw hashmarks differently depending on screen geometry.
        if (System.SCREEN_SHAPE_ROUND == _screenShape) {
            var outerRad = width / 2;
            var innerRad = outerRad - 10;
            // Loop through each 15 minute block and draw tick marks.
            for (var i = Math.PI / 6; i <= 11 * Math.PI / 6; i += (Math.PI / 3)) {
                // Partially unrolled loop to draw two tickmarks in 15 minute block.
                var sY = outerRad + innerRad * Math.sin(i);
                var eY = outerRad + outerRad * Math.sin(i);
                var sX = outerRad + innerRad * Math.cos(i);
                var eX = outerRad + outerRad * Math.cos(i);
                dc.drawLine(sX, sY, eX, eY);
                i += Math.PI / 6;
                sY = outerRad + innerRad * Math.sin(i);
                eY = outerRad + outerRad * Math.sin(i);
                sX = outerRad + innerRad * Math.cos(i);
                eX = outerRad + outerRad * Math.cos(i);
                dc.drawLine(sX, sY, eX, eY);
            }
        } else {
            var coords = [0, width / 4, (3 * width) / 4, width];
            for (var i = 0; i < coords.size(); i++) {
                var dx = ((width / 2.0) - coords[i]) / (height / 2.0);
                var upperX = coords[i] + (dx * 10);
                // Draw the upper hash marks.
                dc.fillPolygon([[coords[i] - 1, 2],
                                [upperX - 1, 12],
                                [upperX + 1, 12],
                                [coords[i] + 1, 2]]);
                // Draw the lower hash marks.
                dc.fillPolygon([[coords[i] - 1, height - 2],
                                [upperX - 1, height - 12],
                                [upperX + 1, height - 12],
                                [coords[i] + 1, height - 2]]);
            }
        }
        */
    }
    //var testMBL = 0; //for testing

    var update_ran = false;

    //! Handle the update event
    //! @param dc Device context
    public function onUpdate(dc as Dc) as Void {
        var clockTime = System.getClockTime();
        var targetDc = null;

        //var inf_sec = ($.Options_Dict["Infinite Second"] == $.infiniteSecondOptions_size-1);
        var sec_on = $.Options_Dict["Infinite Second Option"] > 0 ;

        if (!sec_on) {_secondHandCounter = 10000000;}
        else if (_secondHandCounter >= 10000000) { //sec_on was off but has been turned on via the menu
            _secondHandCounter = 0;
        }
        
        show_sec= true;
        if (!_isAwake) {_secondHandCounter += 1;}        
        if (!_isAwake && _secondHandCounter > $.infiniteSecondLengths[$.Options_Dict["Infinite Second Option"]] ) { show_sec = false; }
        

        if ((! _isAwake) && ( clockTime.sec < 1 )) {            
            System.println(clockTime.hour +":" + clockTime.min +" - current second hand counter = " + _secondHandCounter);
        }
        update_ran = true;

        //System.println("2C");

        // We always want to refresh the full screen when we get a regular onUpdate call.

        
        sec_width = $.Options_Dict["Wide Second"] ? 2 : 1;
        sec_width_clipbox = sec_width + 1;
        //Storage.getValue("Wide Second") = Storage.getValue("Wide Second") ? true : false;
    
        sec_length = $.Options_Dict["Long Second"] ? width_screen*.475 : width_screen*.175;

        
        
        _fullScreenRefresh = true;
        dc.clearClip();
        if (!_hashMarksDrawn || $.Settings_ran ) {
            $.Settings_ran = false; //reset all the hash marks whenever settings are changed
                                    //because some settings will change hashmarks
            if (null != _hashMarksBuffer) {
                // If we have an offscreen buffer that we are using to draw the background,
                // set the draw context of that buffer as our target.
                targetDc = _hashMarksBuffer.getDc();
                //dc.clearClip();
                _hashMarksDrawn = true;
            } else {
                targetDc = dc;
                _hashMarksDrawn = false;
            }

            System.println(clockTime.hour +":" + clockTime.min + " - Drawing all hashmarks");

            //var width = targetDc.getWidth();
            //if (width < 175) { screen -=5; } //Instinct S adjustment
            //var height = targetDc.getHeight();

            // Fill the entire background with Black.
            targetDc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
            targetDc.fillRectangle(0, 0, dc.getWidth(), dc.getHeight());

            // Draw a grey triangle over the upper right half of the screen.
            //targetDc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_DK_GRAY);
            //targetDc.fillPolygon([[0, 0],
            //                      [targetDc.getWidth(), 0],
            //                      [targetDc.getWidth(), targetDc.getHeight()],
            //                      [0, 0]]);

            // Draw the tick marks around the edges of the screen
            //drawHashMarks(targetDc);
            //targetDc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            //drawHashMarks(targetDc);

            // Draw the do-not-disturb icon if we support it and the setting is enabled
            //if (System.getDeviceSettings().doNotDisturb && (null != _dndIcon)) {
            //    targetDc.drawBitmap(width * 0.75, height / 2 - 15, _dndIcon);
            //}

            /*
            // Use white to draw the hour and minute hands
            targetDc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

            if (_screenCenterPoint != null) {
                // Draw the hour hand. Convert it to minutes and compute the angle.
                var hourHandAngle = (((clockTime.hour % 12) * 60) + clockTime.min);
                hourHandAngle = hourHandAngle / (12 * 60.0);
                hourHandAngle = hourHandAngle * Math.PI * 2;
                targetDc.fillPolygon(generateHandCoordinates(_screenCenterPoint, hourHandAngle, dc.getHeight() / 6, 0, dc.getWidth() / 80));
            }

            if (_screenCenterPoint != null) {
                // Draw the minute hand.
                var minuteHandAngle = (clockTime.min / 60.0) * Math.PI * 2;
                targetDc.fillPolygon(generateHandCoordinates(_screenCenterPoint, minuteHandAngle, dc.getHeight() / 3, 0, dc.getWidth() / 120));
            }



            // Draw the arbor in the center of the screen.
            targetDc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
            targetDc.fillCircle(width / 2, height / 2, 7);
            targetDc.setColor(Graphics.COLOR_BLACK,Graphics.COLOR_BLACK);
            targetDc.drawCircle(width / 2, height / 2, 7);

            // Draw the 3, 6, 9, and 12 hour labels.
            var font = _font;
            if (font != null) {
                targetDc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_DK_GRAY);
                targetDc.drawText(width / 2, 2, font, "12", Graphics.TEXT_JUSTIFY_CENTER);
                targetDc.drawText(width - 2, (height / 2) - 15, font, "3", Graphics.TEXT_JUSTIFY_RIGHT);
                targetDc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
                targetDc.drawText(width / 2, height - 30, font, "6", Graphics.TEXT_JUSTIFY_CENTER);
                targetDc.drawText(2, (height / 2) - 15, font, "9", Graphics.TEXT_JUSTIFY_LEFT);
            }
            */            

            targetDc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            
            var drawHashes = true;
            var drawHours = true;
            var avoidCircle = $.Options_Dict["Show Date"] ? true : false;
            
            if (($.Options_Dict["Second Hashes"] && $.Options_Dict["Long Second"]) || !$.Options_Dict["Hour Hashes"] ) { drawHashes = false;} //Don't draw hour hashes if LONG SECOND HAND & SECOND HASHES (they overlap) OR if they are just turned off.

            if (!$.Options_Dict["Hour Numbers"]) {drawHours = false;}

            drawHashMarks(targetDc, drawHashes, drawHours, avoidCircle);
            
            if ($.Options_Dict["Second Hashes"]) {
                if (sec_length<50) {
                    //[:dc=dc, :radius=radius, :includeOnes=include, length1, width1, includeFives, length5, width5, avoidCircle,squeezeX, squeezeY]
                    drawSecondHashMarks({:dc=>targetDc,:radius=>sec_length + 5
                    ,:includeOnes=> true,
                    :length1=>2, :width1=>1, :includeFives=>true, :length5=>5, :width5=>2, :avoidCircle=>false, :squeezeX=>false, :squeezeY=>false});
                } else {
                    var l = 100;
                    var sub1 = 13;
                    var sub2 = 10;

                    if (width_screen < 175) { //Instinct 2S
                        l = 85;
                        sub1 = 14;
                        sub2 = 7;
                    }
                    var ac = $.Options_Dict["Show Date"] ? true : false;
                    //drawSecondHashMarks(targetDc, l, true, l - sec_length - 15, 1, true, l-sec_length-12, 2, true, true, true);
                    drawSecondHashMarks({:dc=>targetDc,:radius=>l,:includeOnes=> true,
                    :length1=>l-sec_length-sub1, :width1=>2, :includeFives=>true, :length5=>l-sec_length-sub2, :width5=>6, :avoidCircle=>ac, :squeezeX=>true, :squeezeY=>true});
                }
                //drawSecondHashMarks(dc, radius, includeOnes, length1, width1, includeFives, length5, width5)
            }
            
        } 

        if (null != _offscreenBuffer) {
            // If we have an offscreen buffer that we are using to draw the background,
            // set the draw context of that buffer as our target.
            targetDc = _offscreenBuffer.getDc();
            
        } else {
            //dc.clearClip();            
            targetDc = dc;            
        }

        if (null != _hashMarksBuffer) {
            targetDc.drawBitmap(0, 0, _hashMarksBuffer);
        }        



        var info = null;
        var moveBarLevel = 0;
        var moveExpired = false;
        if ($.Options_Dict["Show Move"]) {
            info = Toybox.ActivityMonitor.getInfo();
            moveBarLevel = info.moveBarLevel;
            moveExpired = (moveBarLevel != null && moveBarLevel >= 5);
        
            //FOR TESTING
            /*
            testMBL += 1;
            if (testMBL > 5) {testMBL=0;}
            moveExpired  = false;
            if (testMBL>=5) { moveExpired = true; }
            moveBarLevel = testMBL;
            */
            //FOR TESTING
        }
        //moveExpired = true; //for testing
        if ($.Options_Dict["Show Move"]  && moveExpired  )
        {
            drawMove(targetDc, Gfx.COLOR_WHITE);
            //drawMoveDots(targetDc, info.moveBarLevel, Gfx.COLOR_WHITE);
            if ($.Options_Dict["Show Date"]) {
                drawDate(targetDc, Gfx.COLOR_WHITE, true);
            }
            

        } else {
            
            //drawMove(targetDc, Gfx.COLOR_WHITE);
            if ($.Options_Dict["Show Battery"]) {
                drawBattery(targetDc, Gfx.COLOR_WHITE, Gfx.COLOR_BLACK, Gfx.COLOR_WHITE);
            }
            if ($.Options_Dict["Show Move"]) { 
                drawMoveDots(targetDc, moveBarLevel, Gfx.COLOR_WHITE);
            }
            if ($.Options_Dict["Show Date"]) {
                drawDate(targetDc, Gfx.COLOR_WHITE, false);
            }
        }        
        

        //drawDate(targetDc, Gfx.COLOR_WHITE);        
        drawHands(targetDc, clockTime.hour, clockTime.min, clockTime.sec, Gfx.COLOR_WHITE, Gfx.COLOR_WHITE, Gfx.COLOR_WHITE);
        
        targetDc.setClip(width_screen/2 - 7, height_screen/2 -7, 14, 14);
        // Draw the inner circle (at center of the 3 hands)
        targetDc.setColor(Gfx.COLOR_WHITE, background_color);
        targetDc.fillCircle(width_screen/2, height_screen/2, 6);
        targetDc.setColor(background_color,background_color);
        targetDc.drawCircle(width_screen/2, height_screen/2, 6);

        

        // Output the offscreen buffers to the main display if required.
        drawBackground(dc);

        // Draw analog time
        

        // Draw the battery percentage directly to the main screen.
        //var dataString = (System.getSystemStats().battery + 0.5).toNumber().toString() + "%";
        //dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        //dc.drawText(width / 2, 3 * height / 4, Graphics.FONT_TINY, dataString, Graphics.TEXT_JUSTIFY_CENTER);

        

        

        if (_partialUpdatesAllowed && sec_on) {
            // If this device supports partial updates and they are currently
            // allowed run the onPartialUpdate method to draw the second hand.
            onPartialUpdate(dc); //apparently this is a double call (the OS will do the partial update??!!?)
        } else if (_isAwake && sec_on) {
            // Otherwise, if we are out of sleep mode, draw the second hand
            // directly in the full update method.
            /*
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var secondHand = (clockTime.sec / 60.0) * Math.PI * 2;

            if (_screenCenterPoint != null) {
                dc.fillPolygon(generateHandCoordinates(_screenCenterPoint, secondHand, dc.getHeight() / 4, 20, dc.getWidth() / 120));
            }
            */
            var secondHand = (clockTime.sec / 60.0) * Math.PI * 2;

                    // Draw the seconds
            
            //sec = ( clock_sec / 60.0) *  Math.PI * 2;
            dc.setColor(sec_color, Gfx.COLOR_TRANSPARENT);
            drawHand(dc, secondHand, sec_length, sec_width, -5, false, sec_width, false, false);
            //drawHand(dc, secondHand, -15, sec_width, 7, false, true);
            


        }


        _fullScreenRefresh = false;
    }

    //! Draw the date string into the provided buffer at the specified location
    //! @param dc Device context
    //! @param x The x location of the text
    //! @param y The y location of the text
    private function drawDateString(dc as Dc, x as Number, y as Number, reverse as Boolean) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_LONG);
        var dateStr = Lang.format("$1$ $2$ $3$", [info.day_of_week, info.month, info.day]);
        if (reverse) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            if (width_screen >= 175)  {
                dc.drawCircle(144, 34, 34); 
            } else {
                dc.drawCircle(130, 27, 27);  //Instinct S, smaller screen & weird. center of circle is about  128,26 & radius 26
            }
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, Graphics.FONT_MEDIUM, dateStr, Graphics.TEXT_JUSTIFY_CENTER);
        } else {

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, Graphics.FONT_MEDIUM, dateStr, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
    //var sec_colorset = false;
    //var sec_set = false;
    var sec_counter = 0;
    var show_sec = true;
    
    //! Handle the partial update event
    //! @param dc Device context
    public function onPartialUpdate(dc as Dc) as Void {
        // If we're not doing a full screen refresh we need to re-draw the background
        // before drawing the updated second hand position. Note this will only re-draw
        // the background in the area specified by the previously computed clipping region.
        
        if (!show_sec) {return;}

        //System.println("3C");
        if (!_fullScreenRefresh) {
            drawBackground(dc);
        }
        // else {




        //System.println("Ref Clock sec: " + System.getClockTime().sec + " : " + _fullScreenRefresh);
        /*
        //Setting the color takes an amazing amt of CPU cycles. Therefore we set it once only
        //after the main update method has run & messed it up
        if (update_ran ) {
            dc.setColor(sec_color, Gfx.COLOR_TRANSPARENT);
            sec_counter = System.getClockTime().sec;            
            //System.println("Clock sec: " + sec_counter);
        } else {
            sec_counter +=1;
            //System.println("Counter sec: " + sec_counter);
            sec_counter = sec_counter % 60;
            //System.println("Mod sec: " + sec_counter);
        }
        update_ran = false;
        */

        dc.setColor(sec_color, Gfx.COLOR_TRANSPARENT);
        sec_counter = System.getClockTime().sec;            
        //if (sec_counter ==0 && !_fullScreenRefresh) {return;}

        

        if (_screenCenterPoint != null) {
            var secondHand = (sec_counter / 60.0) * Math.PI * 2;
            //drawHand(dc, secondHand, 105, 2, 15, true);
            //var secondHandPoints = generateHandCoordinates(_screenCenterPoint, secondHand,sec_length, 15, sec_width_clipbox);        

            //So, it turns out it is FAR quicker to just blit the entire background in place & then
            //draw the second hand.  All this bound box calculation, getting the clip, etc, is quite slow.
            // Update the clipping rectangle to the new location of the second hand.
            //var curClip = getBoundingBox(secondHandPoints);
            //var bBoxWidth = curClip[1][0] - curClip[0][0] + 1;
            //var bBoxHeight = curClip[1][1] - curClip[0][1] + 1;
            //dc.setClip(curClip[0][0], curClip[0][1], bBoxWidth, bBoxHeight);

            // Draw the second hand to the screen.
            //dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            //dc.fillPolygon(secondHandPoints);

            //drawHands(dc, clockTime.hour, clockTime.min, clockTime.sec, Gfx.COLOR_WHITE, Gfx.COLOR_WHITE, Gfx.COLOR_WHITE);

                    // Draw the seconds
            
            
            //dc.setClip(47, 47, 128,128);
            //sec = ( clock_sec / 60.0) *  Math.PI * 2;
            /*
            switch (sec_counter) {
                case (sec_counter <= 15):
                {
                    dc.setClip(85,5,170,90);
                    break;
                }
                case (sec_counter > 15 && sec_counter <=30):
                {
                    dc.setClip(85, 85, 170,170);
                    break;
                }
                case (sec_counter > 30 && sec_counter <=45):
                {
                    dc.setClip(5, 86, 90,170);
                    break;
                }
                case (sec_counter <=45):
                {
                    dc.setClip(5, 5, 89,89);
                    break;
                }

            }
            */
            //System.println("sec: " + sec_counter);
            /*
            
             if (sec_length> 170) {
             if (sec_counter  == 0 )
                {
                    dc.setClip(85,5,170,90);
                    
                }
            else if (sec_counter ==16 )
                {
                    dc.setClip(85, 85, 170,170);
                    
                }
            else if (sec_counter ==31)
                {
                    dc.setClip(5, 84, 90,170);
                    
                }
            else if (sec_counter ==46)
                {
                    dc.setClip(5, 5, 89,89);
                    
                }
             } else {
                if (sec_counter  == 0 )
                    {
                        dc.setClip(85,35,90,40);
                        
                    }
                else if (sec_counter ==16 )
                    {
                        dc.setClip(85, 85, 140,140);
                        
                    }
                else if (sec_counter==31)
                    {
                        dc.setClip(45, 84, 90,140);
                        
                    }
                else if (sec_counter ==46)
                    {
                        dc.setClip(45, 45, 89,89);
                        
                    }


             }
             */
            
            
            
            //dc.setClip(47, 47, 128,128);

            //drawHand(dc, secondHand,sec_length, 1, 15, true);
            drawHand(dc, secondHand, sec_length, sec_width, -5, false, sec_width,false, false);
            //drawHand(dc, secondHand, -15, sec_width, 7, false);
            //dc.clearClip(); //not good, spikes display time...
            
            

            // Draw the inner circle
            //dc.setColor(Gfx.COLOR_WHITE, background_color);
            //dc.fillCircle(width_screen/2, height_screen/2, 6);
            //dc.setColor(background_color,background_color);
            //dc.drawCircle(width_screen/2, height_screen/2, 6);
        }
    }

    //! Compute a bounding box from the passed in points
    //! @param points Points to include in bounding box
    //! @return The bounding box points
    private function getBoundingBox(points as Array<[Numeric, Numeric]>) as Array<[Numeric, Numeric]> {
        var min = [9999, 9999];
        var max = [0,0];

        for (var i = 0; i < points.size(); ++i) {
            if (points[i][0] < min[0]) {
                min[0] = points[i][0];
            }

            if (points[i][1] < min[1]) {
                min[1] = points[i][1];
            }

            if (points[i][0] > max[0]) {
                max[0] = points[i][0];
            }

            if (points[i][1] > max[1]) {
                max[1] = points[i][1];
            }
        }
        min[0] -= 3;
        min[1] -= 3;
        max[0] += 3;
        max[1] += 3;
 
        return [min, max];
    }

    //! Draw the watch face background
    //! onUpdate uses this method to transfer newly rendered Buffered Bitmaps
    //! to the main display.
    //! onPartialUpdate uses this to blank the second hand from the previous
    //! second before outputting the new one.
    //! @param dc Device context
    private function drawBackground(dc as Dc) as Void {
        //var width = dc.getWidth();
        //var height = dc.getHeight();

        // If we have an offscreen buffer that has been written to
        // draw it to the screen.
        if (null != _offscreenBuffer) {
            dc.drawBitmap(0, 0, _offscreenBuffer);
        }
        /*
        // Draw the date
        if (null != _hashMarksBuffer) {
            // If the date is saved in a Buffered Bitmap, just copy it from there.
            dc.drawBitmap(dc.getWidth()*2/3, 0, _hashMarksBuffer);
        } else {
            // Otherwise, draw it from scratch.
            //drawDateString(dc, width / 2, height / 4);
            drawDate(dc, Gfx.COLOR_WHITE);
        }
        */
        //drawDate(dc, Gfx.COLOR_WHITE);
    }


    //! This method is called when the device re-enters sleep mode.
    //! Set the isAwake flag to let onUpdate know it should stop rendering the second hand.
    public function onEnterSleep() as Void {
        _isAwake = false;
        _secondHandCounter = 0;
        System.println(":"+System.getClockTime().min.format("%02d") + " - Enter Sleep, second hand counter = " + _secondHandCounter);
    }

    //! This method is called when the device exits sleep mode.
    //! Set the isAwake flag to let onUpdate know it should render the second hand.
    public function onExitSleep() as Void {
        _isAwake = true;
        _secondHandCounter = 0; //lets the 2nd hand run for 2 mins *only* after going to sleep
        System.println(":"+System.getClockTime().min.format("%02d") + " - Exit Sleep, second hand counter = " + _secondHandCounter);
        
    }

    //read stored settings & set default values if nothing stored
    public function readStorageValues() as Void {

        var temp = Storage.getValue("Infinite Second Option");        
        $.Options_Dict["Infinite Second Option"] = temp  != null ? temp : $.infiniteSecondOptions_default;
        if ($.Options_Dict["Infinite Second Option"]>$.infiniteSecondOptions_size-1) {$.Options_Dict["Infinite Second Option"] = $.infiniteSecondOptions_default;}
        if ($.Options_Dict["Infinite Second Option"]<0) {$.Options_Dict["Infinite Second Option"] = $.infiniteSecondOptions_default;}
        Storage.setValue("Infinite Second Option",$.Options_Dict["Infinite Second Option"]);

        temp = Storage.getValue("Show Move");
        $.Options_Dict["Show Move"] = temp  != null ? temp : true;
        Storage.setValue("Show Move",$.Options_Dict["Show Move"]);

        temp = Storage.getValue("Show Date");
        $.Options_Dict["Show Date"] = temp  != null ? temp : true;
        Storage.setValue("Show Date",$.Options_Dict["Show Date"]);

        temp = Storage.getValue("Show Battery");
        $.Options_Dict["Show Battery"] = temp  != null ? temp : true;
        Storage.setValue("Show Battery",$.Options_Dict["Show Battery"]);        

        temp = Storage.getValue("Hour Numbers");
        $.Options_Dict["Hour Numbers"] = temp  != null ? temp : true;
        Storage.setValue("Hour Numbers",$.Options_Dict["Hour Numbers"]);

        temp = Storage.getValue("Hour Hashes");
        $.Options_Dict["Hour Hashes"] = temp  != null ? temp : true;
        Storage.setValue("Hour Hashes",$.Options_Dict["Hour Hashes"]);

        temp = Storage.getValue("Second Hashes");
        $.Options_Dict["Second Hashes"] = temp  != null ? temp : true;
        Storage.setValue("Second Hashes",$.Options_Dict["Second Hashes"]);        

        temp = Storage.getValue("Wide Second");
        $.Options_Dict["Wide Second"] = temp  != null ? temp : false;
        Storage.setValue("Wide Second",$.Options_Dict["Wide Second"]);

        temp = Storage.getValue("Long Second");
        $.Options_Dict["Long Second"] = temp  != null ? temp : true;
        Storage.setValue("Long Second",$.Options_Dict["Long Second"]);

        temp = Storage.getValue("Infinite Second");
        $.Options_Dict["Infinite Second"] = temp  != null ? temp : true;
        Storage.setValue("Infinite Second",$.Options_Dict["Infinite Second"]);

        
    }

    

    //! Turn off partial updates
    public function resetSecondHandCounter() as Void {
        _secondHandCounter = 0; 
    }

    //! Turn off partial updates
    public function turnPartialUpdatesOff() as Void {
        _partialUpdatesAllowed = false;
    }

    //! Draw the watch hand
    //! @param dc Device Context to Draw
    //! @param angle Angle to draw the watch hand
    //! @param length Length of the watch hand
    //! @param width Width of the watch hand
    //! @param draw a circle @ the end
    //! @param draw it as a line instead of polygon

    function drawHand(dc, angle, length, width, overheadLine, drawCircleOnTop, drawline, squeezeX, squeezeY)
    {
        
        // Map out the coordinates of the watch hand
        var count = 4;
        var coords = new [count];
        


        if (drawline == 1) {

            coords = [ 
                [0, 0 + overheadLine],
                [0, -length]
            ];
            count = 2;
        
        } else if (drawline == 2) {

            var mult = 1;
            if (!$.Options_Dict["Long Second"]) {mult = 4;}

            coords = [ 
                [-(width/2) * mult, 0 + overheadLine],
                [0, -length],                
                [width/2 * mult, 0 + overheadLine]
            ];
            count = 3;

        } else {
            
            coords = [ 
                [-(width/2), 0 + overheadLine],
                [-(width/2), -length],
                [width/2, -length],
                [width/2, 0 + overheadLine]
            ];
            count = 4;
        }

        var result = new [count];
        var centerX = width_screen / 2;
        var centerY = height_screen / 2;
        //little hand-entry of angle=PI, to make it exact
        var cos = -1;
        var sin = 0;
        //System.println("angle: " + angle);
        if ((Math.PI-angle).abs() > 0.001) {
            cos = Math.cos(angle);
            sin = Math.sin(angle);
        }

        var minY = height_screen;
        var maxY = 0;
        var minX = width_screen;
        var maxX = 0;
        
        // Transform the coordinates
        for (var i = 0; i < count; i += 1)
        {
            var x = (coords[i][0] * cos) - (coords[i][1] * sin);
            var y = (coords[i][0] * sin) + (coords[i][1] * cos);

            var X = centerX + x;
            var Y = centerY + y;

            if (squeezeX) {
                if ((i==0 || i==count-1 )) {
                    if ( X>width_screen-5 ) {
                        X = width_screen-5;
                        if (Y<height_screen/2-4) {Y+=1;}
                        else if (Y>height_screen/2+4) {Y-=1;}
                        
                    }
                    if (X<5) {
                        X=5;
                        if (Y<height_screen/2-4) {Y+=1;}
                        else if (Y>height_screen/2 + 4) {Y-=1;}
                    }
                } else {
                    //if ( X>width_screen ) {X = width_screen;}
                    //if (X<1) {X=1;}
                }
            }
            if (squeezeY) {
                if ((i==0 || i==count-1 )) {
                    if ( Y>height_screen-4 ) {
                        Y = height_screen-4;
                        if (X<width_screen/2-4) {X+=1;}
                        else if (X>width_screen/2  + 4) {X-=1;}
                    }
                    if (Y<4) {
                        Y=4;
                        if (X<width_screen/2 - 4) {X+=1;}
                        else if (X>width_screen/2 - 4) {X-=1;}
                    }
                } else {
                    //if ( Y>height_screen ) {Y = height_screen;}
                    //if (Y<1) {Y=1;}
                }
            }          
            
            result[i] = [ X , Y];
            if (Y<minY) {minY = Y;}
            if (Y>maxY) {maxY = Y;}
            if (X<minX) {minX = X;}
            if (X>maxX) {maxX = X;}

            /*
            if(drawCircleOnTop)
            {   
                if(i == 0)
                {
                    var xCircle = ((coords[i][0]+(width/2)) * cos) - ((coords[i][1] + 1) * sin);
                    var yCircle = ((coords[i][0]+(width/2)) * sin) + ((coords[i][1] + 1) * cos);
                    dc.fillCircle(centerX + xCircle, centerY + yCircle, (width/2));
                }
                else if(i == 1)
                {
                    var xCircle = ((coords[i][0]+(width/2)) * cos) - ((coords[i][1] + 1) * sin);
                    var yCircle = ((coords[i][0]+(width/2)) * sin) + ((coords[i][1] + 1) * cos);
                    dc.fillCircle(centerX + xCircle, centerY + yCircle, (width/2));
                }
                
            }
            */
        }
        dc.setClip(minX  -4 ,minY -4,maxX-minX + 8,maxY-minY + 8);
        //System.println("polygon:" + result);
        // Draw the polygon
        if (drawline== 1) {
            dc.drawLine(result[0][0], result[0][1], result[1][0], result[1][1]);            
        }
        else if (drawline == 2 ){
            //dc.drawLine(result[0][0], result[0][1], result[1][0], result[1][1]);
            //if (drawline>1) { dc.drawLine(result[3][0], result[3][1], result[1][0], result[1][1]);}
            //dc.fillPolygon([[result[0][0], result[0][1]],[result[1][0], result[1][1]],[result[2][0], result[2][1]]]);                    

            dc.fillPolygon(result);

        } else {
             dc.fillPolygon(result);
        }

        //dc.fillPolygon(result);
        return result;
    }

    function drawHands(dc, clock_hour, clock_min, clock_sec, hour_color, min_color, sec_color)
    {
        var hour, min, sec;

        // Draw the hour. Convert it to minutes and
        // compute the angle.
        hour = ( ( ( clock_hour % 12 ) * 60 ) + clock_min );
        hour = hour / (12 * 60.0);
        hour = hour * Math.PI * 2;
        dc.setColor(hour_color, Gfx.COLOR_TRANSPARENT);
        drawHand(dc, hour, width_screen*.41 * .6, 5, 15, false, 0,false, false);

        // Draw the minute
        min = ( clock_min / 60.0) * Math.PI * 2;
        dc.setColor(min_color, Gfx.COLOR_TRANSPARENT);
        drawHand(dc, min, width_screen*.41, 4, 15, false, 0,false, false);

        //System.println("hr,min:" + hour + ", " + min);

        /*
        // Draw the seconds
        if(showSecond){
            sec = ( clock_sec / 60.0) *  Math.PI * 2;
            dc.setColor(sec_color, Gfx.COLOR_TRANSPARENT);
            drawHand(dc, sec, 105, 2, 15, true);
        }

        // Draw the inner circle
        dc.setColor(Gfx.COLOR_WHITE, background_color);
        dc.fillCircle(width_screen/2, height_screen/2, 6);
        dc.setColor(background_color,background_color);
        dc.drawCircle(width_screen/2, height_screen/2, 6);
        */
    }


    //! Draw the hash mark symbols on the watch
    //! @param dc Device context
    function drawHashMarks(dc, drawHashes, drawHours, avoidCircle)
    {
        if (drawHours) {
            // Draw the numbers
            var adj1 = 0;
            var adj2 = 0;
            if (width_screen < 175) {
                adj1 = -2;
                adj2 = -1;
            }
            var font = Gfx.FONT_LARGE;
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_BLACK);
            dc.drawText((width_screen/2), 0, font, "12",Gfx.TEXT_JUSTIFY_CENTER);
            dc.drawText(width_screen + adj1, height_screen/2, font, "3 ", Gfx.TEXT_JUSTIFY_RIGHT + Gfx.TEXT_JUSTIFY_VCENTER);
            dc.drawText(width_screen/2, height_screen-31, font, "6", Gfx.TEXT_JUSTIFY_CENTER);
            dc.drawText(adj2, height_screen/2, font, " 9",Gfx.TEXT_JUSTIFY_LEFT + Gfx.TEXT_JUSTIFY_VCENTER);
        }

        if (drawHashes) {
            
            for(var i = 0; i < 12; i += 1)
            {
                if(i != 0 && i != 3 && i != 6 && i != 9 && ( !avoidCircle || (i != 1 && i != 2 )))
                {
                    var adder = 0;
                    var width_adder = 0;
                    if (width_screen<175) {
                        if (i==1) { adder = 3; width_adder = 4;}
                        if (i==2) {adder = -7;}
                    } else {
                        if (i==1) { adder = -2; width_adder = 0;}
                        if (i==2) {adder = -1;}
                    }
                    drawHand(dc, hashMarksArray[i][0], 100, 2 + width_adder, hashMarksArray[i][1]+adder, false, 0, false, false);
                    //drawHand(dc, angle, length, width, overheadLine, drawCircleOnTop)
                    
                }
            }
        }
    }

    //! Draw the hash mark symbols on the watch
    //! @param dc Device context
    // [:dc=dc, :radius=radius, :includeOnes=include, length1, width1, includeFives, length5, width5, avoidCircle,squeezeX, squeezeY]
    function drawSecondHashMarks(options)
    {

        for(var i = 0; i < 60; i += 1)
        {
            if (options[:avoidCircle] && i >2 && i < 13 ){
                continue;
            }
            //System.println("SecondHash: " + i/5);
            var angle = i/60.0 * Math.PI * 2;
            if(i %5 == 0  )
            {
                
                if (options[:includeFives]) {
                    var drawline = 0;
                    if (options[:width5] == 1) {drawline = 1;}

                    drawHand(options[:dc], angle, options[:radius], options[:width5], options[:length5] - options[:radius], false, drawline,options[:squeezeX],options[:squeezeY]);                    
                    //drawHand(dc, angle, length, width, overheadLine, drawCircleOnTop, drawline, squeezeX, squeezeY)
                }
                
            } else {
                if (options[:includeOnes]) {
                    var drawline = 0;
                    if (options[:width5] == 1) {drawline = 1;}

                    drawHand(options[:dc], angle, options[:radius], options[:width1], options[:length1] - options[:radius], false, drawline,options[:squeezeX],options[:squeezeY]);                    
                }
            }
        }
    }    
    
    function drawBattery(dc, primaryColor, lowBatteryColor, fullBatteryColor)
    {
        var battery = Sys.getSystemStats().battery;
        
        if(battery < 15.0)
        {
            primaryColor = lowBatteryColor;
        }
        //else if(battery == 100.0)
        //{
        //    primaryColor = fullBatteryColor;
        //}

        dc.setColor(primaryColor, Gfx.COLOR_TRANSPARENT);
        dc.drawRectangle(batt_x, batt_y, batt_width_rect, batt_height_rect);
        dc.setColor(background_color, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(batt_x_small-1, batt_y_small+1, batt_x_small-1, batt_y_small + batt_height_rect_small-1);

        dc.setColor(primaryColor, Gfx.COLOR_TRANSPARENT);
        dc.drawRectangle(batt_x_small, batt_y_small, batt_width_rect_small, batt_height_rect_small);
        dc.setColor(background_color, Gfx.COLOR_TRANSPARENT);
        dc.drawLine(batt_x_small, batt_y_small+1, batt_x_small, batt_y_small + batt_height_rect_small-1);

        dc.setColor(primaryColor, Gfx.COLOR_TRANSPARENT);
        dc.fillRectangle(batt_x, batt_y, (batt_width_rect * battery / 100), batt_height_rect);
        if(battery == 100.0)
        {
            dc.fillRectangle(batt_x_small, batt_y_small, batt_width_rect_small, batt_height_rect_small);
        }
    }

    function drawMove(dc, text_color)
    {
        
        var dateStr1 = "MOVE!";
        dc.setColor(text_color, Gfx.COLOR_BLACK);        
        
        dc.drawText(width_screen * .5, batt_y - 1.8 * batt_height_rect , Gfx.FONT_SYSTEM_XTINY, dateStr1, Gfx.TEXT_JUSTIFY_CENTER);      
    }



    function drawMoveDots(dc, numDots, text_color)
    {
        if (numDots<1) { return; }
        dc.setColor(text_color, Gfx.COLOR_BLACK);  
        if ( numDots>4 ) { numDots = 4;   }
        for (var i = 0; i < numDots; i++) {
            var xx = dmd_x + i * dmd_w4;            
            dc.fillRectangle(xx, dmd_yy, dmd_w, dmd_h);            
        }
        
        
    }

    function drawDate(dc, text_color, reverse as Boolean)
    {
        var now = Time.now();
        var info = Calendar.info(now, Time.FORMAT_LONG);
        //var dateStr = Lang.format("$1$ $2$ $3$", [info.day_of_week, info.month, info.day]);

        //dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        //dc.drawRectangle(0,0,dc.getWidth(),dc.getHeight());
        
        var dateStr2 = Lang.format("$1$", [info.day.format("%02d")]);
        var dateStr1 = Lang.format("$1$", [info.day_of_week]);

        if (reverse) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            if (width_screen >= 175)  {
                dc.fillCircle(144, 34, 34); 
            } else {
                dc.fillCircle(130, 27, 30);  //Instinct S, smaller screen & weird. center of circle is about  131,27 & radius 27
            }
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            //dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE); //This works better on sim but worse on real watch
        
        } else {
            dc.setColor(text_color, Gfx.COLOR_TRANSPARENT);
            //dc.setColor(text_color, Gfx.COLOR_BLACK);//This works better on sim but worse on real watch
        }
        
        //dc.drawText(width_screen * .15 , (height_screen * -.04), Gfx.FONT_SYSTEM_NUMBER_THAI_HOT, dateStr2, Gfx.TEXT_JUSTIFY_CENTER);
        //dc.drawText(width_screen * .15 , (height_screen * .22), Gfx.FONT_SYSTEM_MEDIUM, dateStr1, Gfx.TEXT_JUSTIFY_CENTER);

        var ws = .82;
        var hs1 = -.03;
        var hs2 = .23;
        var f1 = Gfx.FONT_SYSTEM_NUMBER_THAI_HOT;
        var f2 = Gfx.FONT_SYSTEM_SMALL;

        if (width_screen < 175) {  //case of Instinct S, smaller screen
            ws = .86;
            hs1 = -.01;
            hs2 = .20;
            f1 = Gfx.FONT_SYSTEM_NUMBER_MEDIUM;
            f2 = Gfx.FONT_SYSTEM_TINY;
        }
  
        dc.drawText(width_screen * ws , (height_screen * hs1), f1, dateStr2, Gfx.TEXT_JUSTIFY_CENTER);
        dc.drawText(width_screen * ws , (height_screen * hs2), f2, dateStr1, Gfx.TEXT_JUSTIFY_CENTER);      
        
    }


}

//! Receives watch face events
class AnalogDelegate extends WatchUi.WatchFaceDelegate {
    private var _view as AnalogView;

    //! Constructor
    //! @param view The analog view
    public function initialize(view as AnalogView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    //! The onPowerBudgetExceeded callback is called by the system if the
    //! onPartialUpdate method exceeds the allowed power budget. If this occurs,
    //! the system will stop invoking onPartialUpdate each second, so we notify the
    //! view here to let the rendering methods know they should not be rendering a
    //! second hand.
    //! @param powerInfo Information about the power budget
    public function onPowerBudgetExceeded(powerInfo as WatchFacePowerInfo) as Void {
        System.println("Average execution time: " + powerInfo.executionTimeAverage);
        System.println("Allowed execution time: " + powerInfo.executionTimeLimit);
        _view.turnPartialUpdatesOff();
    }

    public function onKey(keyEvent) {
        _view.resetSecondHandCounter(); 
        return true;
    }
}

//Note, below doesn't work as watchfaces can't receive button input @ all
class AnalogInputDelegate extends WatchUi.InputDelegate {

    private var _view as AnalogView;

    //! Constructor
    //! @param view The analog view
    public function initialize(view as AnalogView) {
        InputDelegate.initialize();
        _view = view;
    }

    function onKey(keyEvent) {
        _view.resetSecondHandCounter(); 
        System.println("KEY PRESSED!!!!!");
        return false;
    }
}
