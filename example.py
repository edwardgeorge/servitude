from eventlet import api
from servitude import Scheduler
from servitude import servitudecoremidi

def printevent(event):
    print event

s = Scheduler(printevent)
api.spawn(s.run)
ppn = servitudecoremidi.NOTE
s.add_event((ppn*3, 'beat 4'))
s.add_event((ppn*4, 'beat 5'))
s.add_event((ppn*5, 'beat 6'))

def sync(*args):
    # for some reason calling bound methods direct
    # from cython causes a BusError!
    s.sync(*args)

servitudecoremidi.go(sync, 6)
api.get_hub().switch()

