
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
        LEShortField("bp_count", 0),
        BitField("q_id", 0, 8),
        BitField("rank_op", 0, 8),
        LEShortField("flow_id", 0),
        BitField("flow_weight", 0, 8),
        BitField("rank_rst", 0, 8),
        BitField("unused", 0, 32)
    ]
    def mysummary(self):
        return self.sprintf("pkt_len=%pkt_len% src_port=%src_port% dst_port=%dst_port% bp_count=%bp_count% q_id=%q_id% rank_op=%rank_op% flow_id=%flow_id% flow_weight=%flow_weight% rank_rst=%rank_rst%")

bind_layers(Metadata, Raw)

