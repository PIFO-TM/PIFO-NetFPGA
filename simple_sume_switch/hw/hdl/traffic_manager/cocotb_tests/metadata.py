
from scapy.all import Packet, BitField, Raw, bind_layers, LEShortField, LEIntField
# Supress SCAPY warning messages
import logging
logging.getLogger("scapy").setLevel(logging.ERROR)

class Metadata(Packet):
    name = "Metadata"
    fields_desc = [
        LEShortField("pkt_len", 0),
        BitField("src_port", 0, 8),
        BitField("dst_port", 0, 8),
        LEIntField("rank", 0),
        BitField("unused", 0, 64)
    ]
    def mysummary(self):
        return self.sprintf("pkt_len=%pkt_len% src_port=%src_port% dst_port=%dst_port% rank=%rank%")

bind_layers(Metadata, Raw)

