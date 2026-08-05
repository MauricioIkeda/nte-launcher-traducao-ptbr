#ifndef RUNNER_OFFICIAL_LAUNCHER_AUTOMATION_H_
#define RUNNER_OFFICIAL_LAUNCHER_AUTOMATION_H_

#include <string>
#include <vector>

// Runs the elevated, headless official-launcher automation mode. Paths arrive
// as UTF-8 hexadecimal arguments so spaces survive the Windows UAC boundary.
int RunOfficialLauncherAutomation(
    const std::vector<std::string>& command_line_arguments);

#endif  // RUNNER_OFFICIAL_LAUNCHER_AUTOMATION_H_
