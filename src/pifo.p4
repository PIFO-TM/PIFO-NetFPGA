//
// Copyright (c) 2017 Stephen Ibanez
// All rights reserved.
//
// This software was developed by Stanford University and the University of Cambridge Computer Laboratory 
// under National Science Foundation under Grant No. CNS-0855268,
// the University of Cambridge Computer Laboratory under EPSRC INTERNET Project EP/H040536/1 and
// by the University of Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249 ("MRC2"), 
// as part of the DARPA MRC research programme.
//
// @NETFPGA_LICENSE_HEADER_START@
//
// Licensed to NetFPGA C.I.C. (NetFPGA) under one or more contributor
// license agreements.  See the NOTICE file distributed with this work for
// additional information regarding copyright ownership.  NetFPGA licenses this
// file to you under the NetFPGA Hardware-Software License, Version 1.0 (the
// "License"); you may not use this file except in compliance with the
// License.  You may obtain a copy of the License at:
//
//   http://www.netfpga-cic.org
//
// Unless required by applicable law or agreed to in writing, Work distributed
// under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations under the License.
//
// @NETFPGA_LICENSE_HEADER_END@
//


#include <core.p4>
#include "sume_switch.p4"

/*
 * Template P4 project for SimpleSumeSwitch 
 *
 */

typedef bit<48> EthAddr_t; 
typedef bit<32> IPv4Addr_t;

#define IPV4_TYPE 0x0800
#define TCP_TYPE 6

#define SYN_MASK 8w0b0000_0010
#define SYN_POS 1

#define REG_READ 8w0
#define REG_WRITE 8w1

// bp_count register
@Xilinx_MaxLatency(16)
@Xilinx_ControlWidth(1)
extern void bp_count_reg_rw(in bit<1> index,
                            in bit<16> newVal,
                            in bit<8> opCode,
                            out bit<16> result);

// flow_offset register
@Xilinx_MaxLatency(16)
@Xilinx_ControlWidth(1)
extern void flow_offset_reg_rw(in bit<1> index,
                               in bit<16> newVal,
                               in bit<8> opCode,
                               out bit<16> result);

// rank_op register
@Xilinx_MaxLatency(16)
@Xilinx_ControlWidth(1)
extern void rank_op_reg_rw(in bit<1> index,
                           in bit<8> newVal,
                           in bit<8> opCode,
                           out bit<8> result);

#define L2_NUM_FLOWS 9
// init_seqNo register
@Xilinx_MaxLatency(16)
@Xilinx_ControlWidth(L2_NUM_FLOWS)
extern void init_seqNo_reg_rw(in bit<L2_NUM_FLOWS> index,
                              in bit<32> newVal,
                              in bit<8> opCode,
                              out bit<32> result);


// standard Ethernet header
header Ethernet_h { 
    EthAddr_t dstAddr; 
    EthAddr_t srcAddr; 
    bit<16> etherType;
}

// IPv4 header without options
header IPv4_h {
    bit<4> version;
    bit<4> ihl;
    bit<8> tos;
    bit<16> totalLen;
    bit<16> identification;
    bit<3> flags;
    bit<13> fragOffset;
    bit<8> ttl;
    bit<8> protocol;
    bit<16> hdrChecksum;
    IPv4Addr_t srcAddr;
    IPv4Addr_t dstAddr;
}

// TCP header without options
header TCP_h {
    bit<16> srcPort;
    bit<16> dstPort;
    bit<32> seqNo;
    bit<32> ackNo;
    bit<4> dataOffset;
    bit<4> res;
    bit<8> flags;
    bit<16> window;
    bit<16> checksum;
    bit<16> urgentPtr;
}

// List of all recognized headers
struct Parsed_packet { 
    Ethernet_h ethernet; 
    IPv4_h ip;
    TCP_h tcp;
}

// user defined metadata: can be used to shared information between
// TopParser, TopPipe, and TopDeparser 
struct user_metadata_t {
    bit<8>  unused;
}

// digest data to be sent to CPU if desired. MUST be 256 bits!
struct digest_data_t {
    bit<256>  unused;
}

// Parser Implementation
@Xilinx_MaxPacketRegion(16384)
parser TopParser(packet_in b, 
                 out Parsed_packet p, 
                 out user_metadata_t user_metadata,
                 out digest_data_t digest_data,
                 inout sume_metadata_t sume_metadata) {

    state start {
        b.extract(p.ethernet);
        user_metadata.unused = 0;
        digest_data.unused = 0;
        transition select(p.ethernet.etherType) {
            IPV4_TYPE: parse_ipv4;
            default: accept;
        }
    }

    state parse_ipv4 {
        b.extract(p.ip);
        transition select(p.ip.protocol) {
            TCP_TYPE: parse_tcp;
            default: accept;
        }
    }

    state parse_tcp {
        b.extract(p.tcp);
        transition accept;
    }

}

// match-action pipeline
control TopPipe(inout Parsed_packet p,
                inout user_metadata_t user_metadata, 
                inout digest_data_t digest_data, 
                inout sume_metadata_t sume_metadata) {

    action set_output_port(port_t port) {
        sume_metadata.dst_port = port;
    }

    table forward {
        key = { p.ethernet.dstAddr: exact; }

        actions = {
            set_output_port;
            NoAction;
        }
        size = 64;
        default_action = NoAction;
    }


    bit<32> flow_len;
    action set_flow_len(bit<32> len) {
        flow_len = len;
    }

    action set_default_flow_len() {
        flow_len = 0;
    }

    // flow_len_table: used to map IP tos field to flow length
    table flow_len_table {
        key = { p.ip.tos: exact; }

        actions = {
            set_flow_len;
            set_default_flow_len;
        }
        size = 64;
        default_action = set_default_flow_len;
    }

    action log_pkt() {
        sume_metadata.log_pkt = 1;
    }

    // log_pkt_table: used to check if pkt should be logged
    table log_pkt_table {
        key = { p.tcp.flags: ternary; }

        actions = {
            log_pkt;
            NoAction;
        }
        size = 63;
        default_action = NoAction;
    }

    action set_q_id(bit<8> q_id) {
        sume_metadata.q_id = q_id;
    }

    action set_default_q_id() {
        sume_metadata.q_id = 0;
    }

    // lookup_queue_id: used to map rank value to queue ID
    table lookup_queue_id {
        key = { sume_metadata.srpt_rank: ternary; }

        actions = {
            set_q_id;
            set_default_q_id;
        }
        size = 63;
        default_action = set_default_q_id;
    }


    apply {
        forward.apply();

        // set bp_count field
        bp_count_reg_rw(0, 0, REG_READ, sume_metadata.bp_count);

        // check if we should log this packet
        if (p.tcp.isValid()) {
            log_pkt_table.apply();
        }

        if (sume_metadata.dst_port[0:0] == 1 && p.tcp.isValid()) {
            // headed to nf0 so perform rank computation

            // get flowID
            bit<16> flowOffset;
            flow_offset_reg_rw(0, 0, REG_READ, flowOffset);
            bit<16> dport_diff = p.tcp.dstPort - flowOffset;
            bit<L2_NUM_FLOWS> flowID = dport_diff[L2_NUM_FLOWS-1:0];

            bit<32> newVal;
            bit<8> opCode;
            // access the init_seqNo register
            if ((p.tcp.flags & SYN_MASK) >> SYN_POS == 1) {
                newVal = p.tcp.seqNo;
                opCode = REG_WRITE;
            } else {
                newVal = 0; // unused
                opCode = REG_READ;
            }
            bit<32> init_seqNo;
            init_seqNo_reg_rw(flowID, newVal, opCode, init_seqNo);


            // compute srpt rank
            if ((p.tcp.flags & SYN_MASK) >> SYN_POS == 0) { 
                // not a SYN packet

                // lookup flow size
                flow_len_table.apply();

                bit<32> bytes_sent = p.tcp.seqNo - init_seqNo;
    
                // compute srpt rank
                if (flow_len > bytes_sent) {
                    bit<32> bytes_remaining = flow_len - bytes_sent;
                    sume_metadata.srpt_rank = bytes_remaining[31:16]; // increments of 2^16 = 64KB
                } else {
                    sume_metadata.srpt_rank = 0;
                }
            }
            else {
                // not a SYN packet
                sume_metadata.srpt_rank = 0;
            }

            // lookup queue id
            lookup_queue_id.apply();

        }
        else {
            // not headed to nf0
            sume_metadata.srpt_rank = 0;
        }

    }
}

// Deparser Implementation
@Xilinx_MaxPacketRegion(16384)
control TopDeparser(packet_out b,
                    in Parsed_packet p,
                    in user_metadata_t user_metadata,
                    inout digest_data_t digest_data, 
                    inout sume_metadata_t sume_metadata) { 
    apply {
        b.emit(p.ethernet); 
        b.emit(p.ip);
        b.emit(p.tcp);
    }
}


// Instantiate the switch
SimpleSumeSwitch(TopParser(), TopPipe(), TopDeparser()) main;

