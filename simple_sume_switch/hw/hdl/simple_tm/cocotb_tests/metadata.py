
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
        LEShortField("rank", 0),
        LEShortField("bp_count", 0),
        LEIntField("q_id", 0),
        BitField("unused", 0, 32)
    ]
    def mysummary(self):
        return self.sprintf("pkt_len=%pkt_len% src_port=%src_port% dst_port=%dst_port% rank=%rank% bp_count=%bp_count% q_id=%q_id%")

class STFQ_Metadata(Packet):
    name = "STFQ_Metadata"
    fields_desc = [
        LEShortField("pkt_len", 0),
        BitField("src_port", 0, 8),
        BitField("dst_port", 0, 8),
        LEShortField("rank", 0),
        LEShortField("bp_count", 0),
        LEIntField("q_id", 0),
        LEIntField("start_time", 0)
    ]
    def mysummary(self):
        return self.sprintf("pkt_len=%pkt_len% src_port=%src_port% dst_port=%dst_port% rank=%rank% q_id=%q_id% start_time=%start_time%")

bind_layers(Metadata, Raw)
bind_layers(STFQ_Metadata, Raw)

