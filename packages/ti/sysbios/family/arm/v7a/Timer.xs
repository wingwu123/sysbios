/*
 * Copyright (c) 2013, Texas Instruments Incorporated
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * *  Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * *  Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * *  Neither the name of Texas Instruments Incorporated nor the names of
 *    its contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
 * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
/*
 *  ======== Timer.xs ========
 */

var halTimer = null;
var Timer = null;
var Pmu = null;
var BIOS = null;

/*
 *  ======== module$meta$init ========
 */
function module$meta$init()
{
    /* Only process during "cfg" phase */
    if (xdc.om.$name != "cfg") {
        return;
    }

    Timer = this;

    /*
     * set fxntab to false because ti.sysbios.hal.Timer can be used
     * instead of an abstract intsance
     */
    Timer.common$.fxntab = false;

    var GetSet = xdc.module("xdc.services.getset.GetSet");
    GetSet.onSet(this, "availMask", _setTimerAvailMask);
}

/*
 *  ======== instance$meta$init ========
 */
function instance$meta$init(id, tickfxn)
{
    Pmu = xdc.module("ti.sysbios.family.arm.v7a.Pmu");

    /* Need to set PMU interruptFunc early to force Hwi creation */
    Pmu.interruptFunc = Timer.oneShotStub;//'&ti_sysbios_family_arm_v7a_Timer_oneShotStub__E';
}

/*
 *  ======== module$use ========
 */
function module$use()
{
    BIOS = xdc.useModule('ti.sysbios.BIOS');
    Pmu = xdc.useModule("ti.sysbios.family.arm.v7a.Pmu");

    /*
     *  This is to force ti_sysbios_hal_Timer_startup() to be called from
     *  BIOS_start(). hal/Timer_startup will call the proxy_Timer_startup.
     *  This is required for the Timer to startup.
     */
    halTimer = xdc.useModule("ti.sysbios.hal.Timer");
}

/*
 *  ======== module$static$init ========
 */
function module$static$init(mod, params)
{
    mod.availMask = Timer.availMask;

    if (params.anyMask > mod.availMask) {
        Timer.$logError("Incorrect anyMask (" + params.anyMask
            + "). Should be <= " + mod.availMask + ".", Timer, "anyMask");
    }

    mod.handle = null;

    /*
     * if this timer module is not the hal.Timer delegate,
     * plug Timer.startup into BIOS.startupFxns array
     */
    if (halTimer.TimerProxy.delegate$.$name !=
        "ti.sysbios.family.arm.v7a.Timer") {
        BIOS.addUserStartupFunction(Timer.startup);
    }
}

/*
 *  ======== instance$static$init ========
 */
function instance$static$init(obj, id, tickFxn, params)
{
    var modObj = this.$module.$object;

    /* set flag because static instances need to be started */
    Timer.startupNeeded = true;

    obj.staticInst = true;

    if ((id >= Timer.NUM_TIMER_DEVICES)) {
        if (id != Timer.ANY) {
            Timer.$logFatal("Invalid Timer ID " + id + "!", this);
        }
    }

    if (id == Timer.ANY) {
        if (Timer.anyMask && modObj.availMask) {
            modObj.availMask = 0;
        }
    }
    else if (modObj.availMask) {
        modObj.availMask = 0;
    }
    else {
        /*
         * If a timer has not been assigned because either the requested timer was
         * unavailable or 'any timer' was requested and none were available...
         */
        Timer.$logFatal("Timer device unavailable.", this);
    }

    obj.runMode       = params.runMode;
    obj.startMode     = params.startMode;
    obj.periodType    = params.periodType;
    obj.arg           = params.arg;
    obj.tickFxn       = tickFxn;
    obj.period        = params.period;

    if ((params.runMode == Timer.RunMode_CONTINUOUS) ||
        (params.runMode == Timer.RunMode_DYNAMIC)) {
        Pmu.$object.interruptFunc = Timer.periodicStub; //Meta('&ti_sysbios_family_arm_v7a_Timer_periodicStub__E');
    }
    else {
        Pmu.$object.interruptFunc = Timer.oneShotStub;//Meta('&ti_sysbios_family_arm_v7a_Timer_oneShotStub__E');
    }

    modObj.handle = this;
}

/*
 *  ======== getEnumString ========
 *  Get the enum value string name, not 0, 1, 2 or 3, etc.  For an enumeration
 *  type property.
 *
 *  Example usage:
 *  if obj contains an enumeration type property "Enum enumProp"
 *
 *  view.enumString = getEnumString(obj.enumProp);
 *
 */
function getEnumString(enumProperty)
{
    /*
     *  Split the string into tokens in order to get rid of the huge package
     *  path that precedes the enum string name. Return the last 2 tokens
     *  concatenated with "_"
     */
    var enumStrArray = String(enumProperty).split(".");
    var len = enumStrArray.length;
    return (enumStrArray[len - 1]);
}

/*
 *  ======== viewInitBasic ========
 *  Initialize the 'Basic' Timer instance view.
 */
function viewInitBasic(view, obj)
{
    var Program = xdc.useModule('xdc.rov.Program');
    var halTimer = xdc.useModule('ti.sysbios.hal.Timer');

    view.halTimerHandle = halTimer.viewGetHandle(obj.$addr);
    view.label          = Program.getShortName(obj.$label);
    view.startMode      = getEnumString(obj.startMode);
    view.runMode        = getEnumString(obj.runMode);
    view.period         = "0x" + Number(obj.period).toString(16);
    view.periodType     = getEnumString(obj.periodType);
    view.tickFxn        = Program.lookupFuncName(Number(obj.tickFxn));
    view.arg            = obj.arg;

    view.extFreq        =
        Number(obj.extFreq.lo + (obj.extFreq.hi << 32)).toString(10);
}

/*
 *  ======== _setTimerAvailMask ========
 *  The "real-time" setter setTimerAvailMask function
 *
 *  This function is called whenever availMask changes.
 */
function _setTimerAvailMask(field, val)
{
    if ((val != 0) && (val != 1)) {
        this.$logFatal("Invalid availMask " + val + ". This module manages " +
                "a single timer and valid availMask values are 0 or 1.",
                DMTimer);
    }
}
