/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Musify is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Musify is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Musify, including how to contribute,
 *     please visit: https://github.com/gokadzev/Musify
 */

import 'package:flutter/animation.dart';

/// The durations and curves of Zenify's own animations, so the app moves at
/// one pace.
abstract final class Motion {
  /// Presses, highlights and icons changing.
  static const short = Duration(milliseconds: 150);

  /// Things appearing, resizing or taking each other's place.
  static const medium = Duration(milliseconds: 300);

  /// Big moves: panels opening, the cover flipping, lyrics scrolling.
  static const long = Duration(milliseconds: 450);

  /// Quick at first, settling gently.
  static const curve = Curves.easeOutCubic;

  /// For a move there and back.
  static const both = Curves.easeInOutCubic;
}
