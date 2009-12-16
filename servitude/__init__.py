import time

import scheduler

class Scheduler(scheduler.Scheduler):
    def __init__(self, *args, **kwargs):
        super(Scheduler, self).__init__(*args, **kwargs)
        self.bpm = 120
        self.clocks = 0
        self._lastrecalc=None

    def _seconds_per_clock(self):
        return 60.0 / (self.bpm * 24)

    def next_event(self):
        clocks = self.curpos()
        if self.events:
            clock = self.events[0][0]
            diff = clock - self.clocks
            if diff <= 0:
                return 0
            else:
                s = self._seconds_per_clock()
                return time.time() + (s * diff)
        else:
            return None

    def curpos(self):
        ctime = time.time()
        lu = self._lastrecalc
        if not lu:
            return 0
        diff = ctime - lu
        spc = self._seconds_per_clock()
        clocks = diff / spc
        clocks = int(clocks)
        self.clocks = self.clocks + clocks
        self._lastrecalc = lu + (clocks * spc)
        return self.clocks

    def sync(self, clockpos, bpm):
        if not self._lastrecalc:
            self.clocks = clockpos
            self._lastrecalc = time.time()
            self.wake()
            return

        clocks = self.curpos()
        advanced = clockpos > clocks
        self.clocks = clockpos
        self._lastrecalc = time.time()
        self.bpm = bpm
        if advanced:
            self.wake()

