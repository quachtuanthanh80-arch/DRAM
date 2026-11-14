# Lớp test cơ sở cho pyuvm: quản lý RNG theo UVM_SEED và ghi báo cáo JSON
import os
import random
from pathlib import Path
from pyuvm import ConfigDB, uvm_test

from .report_json import git_head_commit


class BaseQShieldTest(uvm_test):
    """Test cơ sở cho mọi kịch bản pyuvm Q-Shield, đọc UVM_SEED và xuất log chuẩn hóa."""

    ENV_NAME = "base"

    def __init__(self, name, parent):
        super().__init__(name, parent)
        self.seed = int(os.environ.get("UVM_SEED", "1001"))
        self.rng = random.Random(self.seed)
        self.root_dir = Path(__file__).resolve().parents[3]
        out_env = os.environ.get("UVM_SEED_JSON", "")
        self.seed_json_path = (
            Path(out_env)
            if out_env
            else self.root_dir / "build" / f"uvm_{self.ENV_NAME}" / f"seed_{self.seed}.json"
        )

    def build_phase(self):
        super().build_phase()
        ConfigDB().set(None, "*", "UVM_SEED", self.seed)
        ConfigDB().set(None, "*", "UVM_RNG", self.rng)
        ConfigDB().set(None, "*", "SEED_JSON_PATH", self.seed_json_path)
        ConfigDB().set(None, "*", "ROOT_DIR", self.root_dir)
        self.logger.info(
            f"[SEED] env={self.ENV_NAME} seed={self.seed} commit={git_head_commit(self.root_dir)[:12]}"
        )
