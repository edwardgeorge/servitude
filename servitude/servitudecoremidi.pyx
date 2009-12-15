from stdlib cimport *
from python cimport *

cdef extern from "CoreFoundation/CFBase.h":
    ctypedef unsigned char Boolean
    ctypedef unsigned int Byte
    ctypedef unsigned short UInt16
    ctypedef unsigned int UInt32
    ctypedef unsigned long UInt64
    ctypedef unsigned int OSStatus
    ctypedef void* CFTypeRef
    ctypedef CFTypeRef CFStringRef

cdef extern from "CoreFoundation/CFString.h":
    ctypedef UInt32 CFStringEncoding

    CFStringRef CFStringCreateWithCString(
        void* alloc,
        char* cStr,
        CFStringEncoding encoding)

    Boolean CFStringGetCString(
        CFStringRef theString,
        char *buffer,
        int bufferSize,
        CFStringEncoding encoding)

    void CFRelease(CFTypeRef cf)

cdef extern from "CoreMIDI/MIDIServices.h":
    ctypedef void* MIDIObjectRef
    ctypedef MIDIObjectRef MIDINotification
    ctypedef MIDIObjectRef MIDIClientRef
    ctypedef MIDIObjectRef MIDIDeviceRef
    ctypedef MIDIObjectRef MIDIEndpointRef
    ctypedef MIDIObjectRef MIDIPortRef

    ctypedef UInt64 MIDITimeStamp

    ctypedef struct MIDIPacket:
        MIDITimeStamp timeStamp
        UInt16 length
        Byte data[256]

    ctypedef struct MIDIPacketList:
        UInt32       numPackets
        MIDIPacket*   packet

    ctypedef void (*MIDINotifyProc)(MIDINotification *message, void *refCon)
    ctypedef void (*MIDIReadProc)(MIDIPacketList *pktlist, void *readProcRefCon,
        void *srcConnRefCon)

    OSStatus MIDIClientCreate(
        CFStringRef name,
        MIDINotifyProc notifyProc,
        void* notifyRefCon,
        MIDIClientRef* outClient) 

    OSStatus MIDISourceCreate(
        MIDIClientRef client,
        CFStringRef name,
        MIDIEndpointRef* outsrc)

    OSStatus MIDIInputPortCreate(
        MIDIClientRef client,
        CFStringRef portName,
        MIDIReadProc readProc,
        void* refCon,
        MIDIPortRef* outPort)

    OSStatus MIDIOutputPortCreate(
        MIDIClientRef client,
        CFStringRef portName,
        MIDIPortRef* outPort)

    OSStatus MIDIPortConnectSource(
        MIDIPortRef port,
        MIDIEndpointRef source,
        void* connRefCon)

    OSStatus MIDIObjectGetStringProperty(
        MIDIObjectRef obj,
        CFStringRef propertyID,
        CFStringRef* str)

    MIDIPacket* MIDIPacketNext(MIDIPacket *pkt)

    int MIDIGetNumberOfDevices()
    int MIDIGetNumberOfSources()
    int MIDIGetNumberOfDestinations()

    MIDIDeviceRef MIDIGetDevice(
        int deviceIndex0)

    MIDIEndpointRef MIDIGetSource(
        int sourceIndex0)

    MIDIEndpointRef MIDIGetDestination(
        int destIndex0)

    CFStringRef kMIDIPropertyName
    CFStringRef kMIDIPropertyManufacturer
    CFStringRef kMIDIPropertyModel

cdef extern from "Python.h":
    void PyEval_InitThreads()
    ctypedef int PyGILState_STATE
    PyGILState_STATE PyGILState_Ensure()
    void PyGILState_Release(PyGILState_STATE gstate)

cdef CFStringRef cfstr(char* cstr):
    return CFStringCreateWithCString(NULL, cstr, 0)

def getnumsources():
    return MIDIGetNumberOfSources()

def getnumdestinations():
    return MIDIGetNumberOfDestinations()

def getnumdevices():
    return MIDIGetNumberOfDevices()

cdef char* getproperty(MIDIObjectRef obj, CFStringRef prop):
    cdef CFStringRef pval
    cdef char val[64]
    MIDIObjectGetStringProperty(obj, prop, &pval)
    CFStringGetCString(pval, val, sizeof(val), 0)
    CFRelease(pval)
    return val

def getdeviceinfo(int devid):
    cdef MIDIDeviceRef dev = MIDIGetDevice(devid)
    cdef CFStringRef *props = [kMIDIPropertyName, kMIDIPropertyManufacturer, kMIDIPropertyModel]

    ret = []
    for i in range(3):
        ret.append(getproperty(dev, props[i]))
    return ret

ctypedef struct timingdata:
    void* callback
    int callbackinterval
    unsigned long clocks
    int started
    MIDITimeStamp lasttimestamp
    MIDITimeStamp* received
    int buflen
    int bufpos
    int age

cdef timingdata* timingdata_create():
    cdef timingdata* td = <timingdata*>malloc(sizeof(timingdata))
    td.clocks = 0
    td.started = 0
    td.buflen = 96
    td.received = <MIDITimeStamp*>malloc(td.buflen * sizeof(MIDITimeStamp))
    td.bufpos = -1
    td.age = -1
    return td

cdef timingdata_free(timingdata *td):
    free(td.received)
    free(td)

cdef void callback(MIDIPacketList *pktlist, void *refCon, void *connRefCon):
    cdef timingdata* td = <timingdata*>refCon
    cdef MIDIPacket *packet = <MIDIPacket *>pktlist.packet
    cdef int i

    cdef PyGILState_STATE gil
    for i in range(pktlist.numPackets):
        if packet.data[0] == 0xF8:  # midi clock
            if td.started == 1:
                handle_clock(td, packet.timeStamp)
        elif packet.data[0] == 0xFA:  # midi start
            if td.started == 0:
                td.clocks == 0
                handle_continue(td)
        elif packet.data[0] == 0xFC:  # midi stop
            if td.started == 1:
                handle_stop(td)
        elif packet.data[0] == 0xFB:  # midi continue
            if td.started == 0:
                handle_continue(td)
        elif packet.data[0] == 0xF2:
            handle_songposition(td, packet)
        else:
            gil = PyGILState_Ensure()
            print 'unknown:', hex(packet.data[0])
            PyGILState_Release(gil)

        packet = MIDIPacketNext(packet)

cdef float _pm = 1000000000.0/60.0

cdef float calculate_bpm(timingdata *td):
    cdef MIDITimeStamp oldest = td.received[((td.bufpos+td.buflen)-td.age)%td.buflen]  # nanoseconds
    cdef unsigned long nanosperbeat = ((td.lasttimestamp - oldest) / td.age) * 96  # beats
    return nanosperbeat / _pm

cdef void handle_clock(timingdata *td, MIDITimeStamp timestamp):
    cdef float bpm
    td.clocks += 1
    td.bufpos = (td.bufpos + 1) % td.buflen
    td.received[td.bufpos] = timestamp
    td.age = td.age + 1
    td.age = td.buflen - 1 if td.age >= td.buflen else td.age
    td.lasttimestamp = timestamp
    if td.age > 0:
        bpm = calculate_bpm(td)

    if td.clocks % td.callbackinterval == 0:
        callbacktopython(td.callback, td.clocks, bpm)

cdef void handle_stop(timingdata *td):
    td.bufpos = -1
    td.age = -1
    td.started = 0

cdef void handle_continue(timingdata *td):
    td.started = 1

cdef void handle_songposition(timingdata *td, MIDIPacket *packet):
    cdef int midibeats
    midibeats = (packet.data[2] & 127) << 7
    midibeats = midibeats | (packet.data[1] & 127)
    td.clocks = midibeats * 6  # 6 clocks in a midi beat

cdef void callbacktopython(void* callback, unsigned long clockpos, float bpm) with gil:
    (<object>callback)(clockpos, bpm)

def go(object callbackfunc, int callbackinterval):
    PyEval_InitThreads()

    cdef timingdata* td = timingdata_create()
    cdef int i
    cdef MIDIClientRef client
    cdef MIDIPortRef inport

    td.callback = <void*>callbackfunc
    td.callbackinterval = callbackinterval

    MIDIClientCreate(cfstr("test"), NULL, NULL, &client)
    MIDIInputPortCreate(client, cfstr("input"), callback, <void*>td, &inport)

    cdef int numsources = MIDIGetNumberOfSources()
    cdef MIDIEndpointRef src
    for i in range(numsources):
        src = MIDIGetSource(i)
        print getproperty(src, kMIDIPropertyName)
        MIDIPortConnectSource(inport, src, NULL)

MIDI_BEAT = 6
QUARTER_NOTE = 24
NOTE = 96

