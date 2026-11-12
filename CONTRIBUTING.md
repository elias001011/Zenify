# Contributing to Zenify

Thank you for considering contributing to this project! We welcome and appreciate all contributions.

## How to Contribute

1. Fork the repository and clone it locally.
2. Create a new branch for your changes.
3. Make your changes and test them thoroughly.
4. Commit your changes and push them to your fork.
5. Open a pull request and describe your changes.

## Before you open a pull request

- **Stay close to Musify.** Zenify follows Musify's code and merges it often.
  A fix for code that comes from Musify belongs in
  [Musify](https://github.com/gokadzev/Musify) first, and reaches Zenify with
  the next merge. In files that come from Musify, change only what you need:
  no re-indenting, renaming or reordering that changes nothing for the user.
- **Test it.** Use the Flutter version set in `pubspec.yaml`. Run
  `flutter analyze` and `flutter test`; both must pass. A fix comes with a test
  that fails without it.
- **Short comments.** One line, only when the reason is not obvious from the
  code.

## Code of Conduct

All contributors are expected to abide by our code of conduct. Please make sure to read and understand the [code of conduct](CODE_OF_CONDUCT.md) before making a contribution.

## Code Reviews

All pull requests will be reviewed by at least one project maintainer. Please be patient and willing to make changes based on feedback.

## Attribution

By contributing to this project, you agree to allow your contributions to be used and distributed under the project's license.

## Questions

If you have any questions about contributing, open an
[issue](https://github.com/elias001011/Zenify/issues).

## Translations

Zenify is translated in the repository itself, with no external translation
platform (there is no `crowdin.yml`). A translation reaches the project as a
pull request that edits the language's ARB file in
[`lib/localization`](https://github.com/elias001011/Zenify/tree/master/lib/localization).

### Files

| File | What it is |
|---|---|
| `lib/localization/app_en.arb` | The template: every key, with its English text. |
| `lib/localization/app_<code>.arb` | One language, for example `app_pt.arb` (Portuguese) or `app_sv.arb` (Swedish). |
| `l10n.yaml` | Tells Flutter where the ARB files are and which one is the template (`app_en.arb`). |
| `lib/localization/untranslated.json` | Generated list of the keys each language still lacks. Git-ignored. |
| `lib/localization/app_*.dart` | Generated Dart code. Git-ignored: do not commit it. |

### Translate a language that already exists

New strings are added to `app_en.arb` and `app_pt.arb` first; the other
languages follow.

1. Open `lib/localization/app_<code>.arb`. To start a file, copy `app_en.arb`
   to it and follow the steps below.
2. Change only the text after each key's colon. Keys (the quoted names before
   the colon) stay exactly as they are. English:

   ```json
   "songFadeSeconds": "{count, plural, =1{1 second} other{{count} seconds}}",
   ```

   Portuguese, from `app_pt.arb`:

   ```json
   "songFadeSeconds": "{count, plural, =1{1 segundo} other{{count} segundos}}",
   ```

3. Placeholders are the words in braces, such as `{minutes}`, `{count}`,
   `{device}` and `{path}`. The app fills them in. Keep each name exactly as
   it is, in braces, and do not translate it. For example, the English
   `"shareRecapText": "My {period} Zenify recap"` keeps `{period}` in every
   language.
4. Plurals use ICU syntax, `{count, plural, =1{...} other{...}}`: `=1` is the
   text for exactly one item, `other` is used for everything else, and
   `{count}` inside it prints the number. Always keep `other`. The repository
   uses only `=1` and `other` today; if your language needs more categories
   (such as `one`, `few` or `many`), check that `flutter gen-l10n` accepts them
   before you open the pull request.
5. Keys that start with `@` describe placeholder types, such as
   `@artistListeningSummary`. Leave them as they are.
6. Do not translate brand names: Zenify, Musify, YouTube, YouTube Music,
   SponsorBlock, Spotify and GitHub stay as they are.
7. If you are not sure of a string, leave the English text in place. A missing
   key is shown in English by the app, so nothing breaks.

### Find what is missing

1. Run `flutter gen-l10n`. `flutter pub get` runs it too, because
   `pubspec.yaml` sets `generate: true`.
2. Open `lib/localization/untranslated.json`. It has one list per language
   with the keys that language's ARB file does not have.
3. A missing key is shown in English. The generated
   `app_localizations_<code>.dart` already contains the English text: for
   example, `aboutForkMaintainer` shows "Fork developer and maintainer" in
   German until someone translates it.

### Add a new language

Use a plain language code, such as `sv` for Swedish. Four places change:

1. **`lib/localization/app_<code>.arb`** (new file): a copy of `app_en.arb`
   with the values translated.
2. **`lib/localization/app_en.arb`**: add the name of the language, as a key
   named `language` followed by the code with its first letter capitalized,
   for example `"languageSv": "Swedish"`. Copy that key into the new file,
   translated. Other languages show the English name until they add theirs.
3. **`lib/utilities/language_utils.dart`**: add the code to the `appLanguages`
   set. The Language picker in Settings lists that set.
4. **`lib/utilities/language_utils.dart`**: add a
   `case '<code>': return l10n.language<Name>;` to the `switch` in
   `getLanguageDisplayName`. Without it, the new language is shown with the
   English name.

Then run `flutter gen-l10n`, `flutter analyze` and the language test below.

### Test it locally

1. Run the app with `flutter run`, on Linux or on an Android device. Use the
   Flutter version set in `pubspec.yaml` (`flutter: ^3.50.0`).
2. In Settings, open **Language** under Preferences and pick your language.
   Go through the screens you changed, and check that the longer strings fit
   in buttons, dialogs and the player.
3. Run `flutter analyze` and `flutter test test/language_switch_test.dart`.
   Both must pass. The test opens the Settings pickers on a phone and checks
   that the Settings page stays on screen.

### Open the pull request

- One language per pull request.
- Title: `Translate Zenify to <Language> (<code>)` for a new language, or
  `Update <Language> translation` for one that exists.
- Change only `lib/localization/app_<code>.arb`. For a new language, also
  change `lib/localization/app_en.arb` and `lib/utilities/language_utils.dart`.
  Do not commit the generated files (`app_localizations*.dart` and
  `untranslated.json`).
- In the description, say how many keys you translated (compare
  `untranslated.json` before and after) and that `flutter analyze` and the
  language test pass. Screenshots of the screens you checked help the review.
