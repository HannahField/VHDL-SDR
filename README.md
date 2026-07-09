# Overview
This project contains the three main architectures for my FPGA based Software Defined Radio transmitter bachelor project. It also includes the full report for my bachelor project, except the front page, as it contains sensitive information.

The project is made for the [Terasic DE25](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=115&No=1354#contents), which is based on an Agilex 5 platform.

## Architecture
This project has 3 different architectures, a simple single-carrier modulation, OFDM and SC-FDMA. They are all based on the same modular, parametric architecture.

### Common Architecture
The common architecture contains a data source, MQAM shaper, and a DAC driver.

The Data Source is a simple module consisting of 1024 bytes of Lorem Ipsum as ASCII, converted to binary as a concatination of bytes as MSB first. On valid_in assertion, the module will output the next log2(MQAM) bits.

The MQAM shaper is parametric, based on a square MQAM grid, up to MQAM = 4096, and is initiated as a generic, meaning it cannot be changed after initiation.

The used DAC is the [THDB-ADA](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=73&No=278&PartNo=1#contents), which fits well with the Terasic DE25. It is a 14-bit, dual channel DAC, which is run at 50 MHz.

The DAC has a few quirks, the most important being that it behaves like a low-pass filter due to the output going through a set of transformers. From experimentation, it behaves as a first-order low-pass filter with critical frequency of 115 kHz. As such, a minimum allowed frequency of 1 MHz for the ouput was settled upon.

### Single-Carrier
The single-carrier implementation is a simple MQAM modulation scheme, utilizing an RRC filter as it's pulse shaper, implemented using a polyphase filter, as it also upsamples the data stream from 5 MSym/s to 50 MHz. It also has a frequency shifter to avoid DC, which involves multiplication with a complex exponential with 5 MHz frequency, pushing the active band to \[1.625 MHz, 8.375 MHz\]. 

A single-carrier implementation is not suitable for high-bandwidth wireless communication without a large effort due to multipath interference.

### OFDM
