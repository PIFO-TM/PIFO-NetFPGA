import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ReadOnly, ReadWrite, ClockCycles
from cocotb.drivers import BusDriver
from cocotb.binary import BinaryValue

class ReqMaster(BusDriver):

    _signals = ["valid"]
    _optional_signals = []


    def __init__(self, entity, name, clock):
        BusDriver.__init__(self, entity, name, clock)

        # Drive default values onto bus
        self.bus.valid.setimmediatevalue(0)


    @cocotb.coroutine
    def write_reqs(self, num_reqs, delay):
        """
        Submit requests
        """
        yield RisingEdge(self.clock)

        for i in range(num_reqs):
            self.bus.valid <= 1
            yield RisingEdge(self.clock)
            self.bus.valid <= 0
            # delay between sucessive requests
            for i in range(delay):
                yield RisingEdge(self.clock)


class ReqSlave(BusDriver):

    _signals = ["valid", "queue", "rd_en"]
    _optional_signals = []


    def __init__(self, entity, name, clock):
        BusDriver.__init__(self, entity, name, clock)

        # Drive default values onto bus
        self.bus.rd_en.setimmediatevalue(0)

        self.reqs = []

    @cocotb.coroutine
    def read_reqs(self, num_reqs):
        """
        Read num_reqs requests
        """
        self.reqs = []

        for i in range(num_reqs):
            yield RisingEdge(self.clock)
            # wait for valid to be asserted
            yield FallingEdge(self.clock)
            while not self.bus.valid.value:
                yield RisingEdge(self.clock)
                yield FallingEdge(self.clock)
            # record output request
            self.reqs.append(self.bus.queue.value.integer)
            yield RisingEdge(self.clock)
            self.bus.rd_en <= 1
            yield RisingEdge(self.clock)
            self.bus.rd_en <= 0









