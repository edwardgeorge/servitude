import bisect
import os
import time

from eventlet import api

class Scheduler(object):
    def __init__(self, eventhandler):
        self.r, self.w = os.pipe()
        self.events = []
        self.accuracy = 0.01
        self.default_sleep = 60
        self.eventhandler = eventhandler

    def run(self):
        while True:
            timeout = self.sleep_timeout()
            if timeout > 0:
                try:
                    api.trampoline(self.r, read=True, timeout=timeout)
                    os.read(self.r, 1024)
                except api.TimeoutError, e:
                    pass
            while self.events and self.next_event() <= (time.time() + self.accuracy):
                event = self.events.pop(0)
                self.eventhandler(event)

    def sleep_timeout(self):
        next = self.next_event()
        if next:
            return (next - time.time()) / 2.0
        else:
            return self.default_sleep

    def next_event(self):
        if self.events:
            return self.events[0][0]
        else:
            return None

    def wake(self):
        os.write(self.w, '\0')

    def add_event(self, event):
        index = bisect.bisect(self.events, event)
        self.events.insert(index, event)
        if index == 0:
            self.wake()

