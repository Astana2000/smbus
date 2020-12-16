# sbmus
Description of SMBus (based on I2c) with PEC. Language - VHDL.
Supports multiple bytes writing/reading.
Both master and slave are programmed as state machines,they have almost identical states.

The program can be synthesized,diagrams are working nicely. However, stop/start/ready states are a little messed up,more testing should be done. 
Code average is around 98 %.
