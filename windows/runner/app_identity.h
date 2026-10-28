#ifndef RUNNER_APP_IDENTITY_H_
#define RUNNER_APP_IDENTITY_H_

// Identify Musify consistently in the Windows shell.
inline constexpr wchar_t kAppUserModelId[] = L"io.github.elias001011.zenify";

// Register the shell identity before creating any windows.
void ConfigureAppIdentity();

#endif  // RUNNER_APP_IDENTITY_H_
