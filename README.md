# Overview
This project contains the three main architectures for my FPGA based Software Defined Radio transmitter bachelor project. It also includes the full report for my bachelor project, except the front page, as it contains personal information.

The project is made for the [Terasic DE25](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=115&No=1354#contents), which is based on an Agilex 5 platform.


Below is summary table of the results and resource utilizations:

|Measure|Single Carrier|OFDM|SC-FDMA|
|---|---|---|---|
|Data Rate|20 Mbit/s|50 Mbit/s|50 Mbit/s|
|Bandwidth|6.75 MHz|13 MHz|13 MHz|
|Spectral Efficiency|2.96 bit/s/Hz|3.85 bit/s/Hz|3.85 bit/s/Hz|
|Payload EVM|-23.8 dB|-36.2 dB|-42.8 dB|
|PAPR|5.15 dB|16.19 dB|7.06 dB|
|ALM Usage|1,475 (3%)|3,895 (8%)|6,009 (13%)|
|RAM Bit Usage|0 (0%)|427,776 (6%)|518,656 (7%)|
|RAM Block Usage|0 (0%)|54 (15%)|88 (25%)|
|DSP Block Usage|27 (14%)|57 (30%)|102 (54%)|
|Slack|8.249 ns|7.030 ns|7.158 ns|


## Architecture
This project has 3 different architectures, a simple single-carrier modulation, OFDM and SC-FDMA. They are all based on the same modular, parametric architecture.

### Common Architecture
The common architecture contains a data source, MQAM shaper, and a DAC driver.

The Data Source is a simple module consisting of 1024 bytes of Lorem Ipsum as ASCII, converted to binary as a concatenation of bytes as MSB first. On valid_in assertion, the module will output the next log2(MQAM) bits.

The MQAM shaper is parametric, based on a square MQAM grid, up to MQAM = 4096, and is initiated as a generic, meaning it cannot be changed after initiation.

The used DAC is the [THDB-ADA](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=73&No=278&PartNo=1#contents), which fits well with the Terasic DE25. It is a 14-bit, dual channel DAC, which is run at 50 MHz.

The DAC has a few quirks, the most important being that it behaves like a low-pass filter due to the output going through a set of transformers. From experimentation, it behaves as a first-order high-pass filter with critical frequency of 115 kHz. As such, a minimum allowed frequency of 1 MHz for the ouput was settled upon.

### Single-Carrier
The single-carrier implementation is a simple MQAM modulation scheme, utilizing an RRC filter as it's pulse shaper, implemented using a polyphase filter, as it also upsamples the data stream from 5 MSym/s to 50 MHz. It also has a frequency shifter to avoid DC, which involves multiplication with a complex exponential with 5 MHz frequency, pushing the active band to \[1.625 MHz, 8.375 MHz\]. 

A single-carrier implementation is not suitable for high-bandwidth wireless communication without a large effort due to multipath interference.

### OFDM
Orthogonal Frequency Division Multiplexing, OFDM, is a modern multicarrier modulation suitable for use in high-bandwidth wireless communication systems due to its resistance to multipath interference, and is widely used, including in WiFi and cellular communication systems.

In modern wireless systems signals get modulated onto high-frequency carrier waves, such as 2.4GHz and 5GHz in WiFi. The idea behind OFDM is to turn a single high-bandwidth signal into several slower signals, which each get modulated onto their own orthogonal carrier. In practice, this is done by parallelizing the signal, and then doing an inverse discrete fourier transform on said parallel symbol. Additionally, a cyclic prefix is added before transmission to combat intersymbol interference.

As such, this OFDM module utilizes the FFT module from [here](https://github.com/HannahField/VHDL-FFT) to perform an IFFT on 256 samples, padded with zeros to a size of 1024. Additionally, there are 10 pilot waves interspersed in the active region.

One of the main issues with OFDM is its high peak-to-average power, which arises from the independent nature of the subcarriers from this approach. This leads to the need for higher quality, and thus more expensive, analog circuitry, such as DACs and amplifiers.

### SC-FDMA
Single-Carrier Frequency Division Multiple Access, SC-FDMA, is a modification to OFDM, which trades complexity for a lower peak-to-average power. This is done by including a DFT precoding, which causes the subcarriers to become deeply correlated.

The DFT precoding is done on 256 samples, and then fed into the previous OFDM module.

## Testing and Verification
The OFDM and SC-FDMA modules are each tested with a testbench.

The full SDRs for all three modulation schemes are tested in hardware, with the outputs from the DAC being sampled by an analog discovery 2 with a BNC breakout board.

The details of the tests can be seen both in Report.pdf, and in /Verification. The clock period for this project is 20 ns. 
