import sys
sys.path.insert(0, '/home/thanh/ramulator2/python')
import ramulator

print("Creating Frontend...")
frontend = ramulator.frontend.SimpleO3(
    clock_ratio=4,
    traces=["/mnt/d/RAM/sim/traces/trace_benign.trace"],
    num_expected_insts=5000,
    translation=ramulator.translation.NoTranslation(max_addr=2147483648),
)

print("Creating DDR4...")
ddr4 = ramulator.dram.DDR4(
    org_preset="DDR4_8Gb_x8",
    timing_preset="DDR4_3200AA",
    rank=2,
    verbose=False,
)

print("Creating Controller...")
ctrl = ramulator.controller.GenericDDR(
    dram=ddr4,
    scheduler=ramulator.scheduler.FRFCFS(),
    refresh_manager=ramulator.refresh_manager.AllBank(),
    row_policy=ramulator.row_policy.Open(),
    addr_mapper=ramulator.addr_mapper.RoBaRaCoCh(),
)

print("Creating Memory System...")
mem = ramulator.memory_system.GenericDRAM(
    clock_ratio=2,
    controllers=[ctrl],
    channel_mapper=ramulator.channel_mapper.CacheLineInterleave(),
)

print("Starting Simulation...")
sim = ramulator.Simulation(frontend, mem)
sim.run()

stats = sim.stats
ctrl_stats = stats["memory_system"]["controller"]
print("\n=== Simulation Results ===")
print(f"Cycles:            {ctrl_stats['cycles']}")
print(f"Avg read latency:  {ctrl_stats['avg_read_latency']:.2f} cycles")
print(f"Read requests:     {ctrl_stats['num_read_reqs']}")
print(f"Write requests:    {ctrl_stats['num_write_reqs']}")
print(f"Row hits:          {ctrl_stats['row_hits']}")
print(f"Row misses:        {ctrl_stats['row_misses']}")
print(f"Row conflicts:     {ctrl_stats['row_conflicts']}")
