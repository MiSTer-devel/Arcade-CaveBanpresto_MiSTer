library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- CaveBanpresto-local, fixed-shape bridge to the production Arcadia
-- single_port_ram primitive used by Sound.sv.
--
-- The shared SystemVerilog CaveSinglePortRam wrapper selects MASK_ENABLE with
-- the strings "TRUE"/"FALSE". Quartus accepts that existing mixed-language
-- form, but ModelSim 10.5b cannot convert the string to the VHDL Boolean
-- generic during elaboration. This parameterless bridge binds the same entity
-- natively in VHDL, so synthesis and simulation use the exact same RAM shape:
-- 13-bit address, 8-bit data, full 8192-word depth, unmasked single port.
entity CaveBanprestoSoundRamPrimitive is
  port (
    clock : in  std_logic;
    rd    : in  std_logic;
    wr    : in  std_logic;
    addr  : in  std_logic_vector(12 downto 0);
    din   : in  std_logic_vector(7 downto 0);
    dout  : out std_logic_vector(7 downto 0)
  );
end entity CaveBanprestoSoundRamPrimitive;

architecture rtl of CaveBanprestoSoundRamPrimitive is
begin
  ram : entity work.single_port_ram
    generic map (
      ADDR_WIDTH  => 13,
      DATA_WIDTH  => 8,
      DEPTH       => 0,
      MASK_ENABLE => false
    )
    port map (
      clk  => clock,
      rd   => rd,
      wr   => wr,
      addr => unsigned(addr),
      mask => (others => '0'),
      din  => din,
      dout => dout
    );
end architecture rtl;
