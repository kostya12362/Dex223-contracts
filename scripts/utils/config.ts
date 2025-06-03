import fs from "fs";

export function loadConfig(cfgPath: string) {
  const raw = fs.readFileSync(cfgPath, "utf8");
  return JSON.parse(raw);
}

export function saveConfig(cfgPath: string, config: any) {
  fs.writeFileSync(cfgPath, JSON.stringify(config, null, 2), "utf8");
}
