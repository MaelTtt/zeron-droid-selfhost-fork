package sh.zeron.android.design

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import uniffi.zeron_core.ColorRole

/**
 * The desktop's "Black Violet (Noctalia)" custom theme, ported from
 * `~/.config/zeron-themes/black-violet` (the dark and light variants the
 * desktop app has selected). Colors are the desktop's resolved values; the
 * few Material roles the desktop doesn't name are derived from its neighbours.
 */
val BlackVioletDark: ColorScheme = darkColorScheme(
    primary = Color(0xFFA277FF),
    onPrimary = Color(0xFF000000),
    primaryContainer = Color(0xFF2D2640),
    onPrimaryContainer = Color(0xFFEDECEE),
    inversePrimary = Color(0xFF7C5CFF),
    secondary = Color(0xFF8B869E),
    onSecondary = Color(0xFF0D0B14),
    secondaryContainer = Color(0xFF1A1426),
    onSecondaryContainer = Color(0xFFEDECEE),
    tertiary = Color(0xFFC4A5FF),
    onTertiary = Color(0xFF000000),
    tertiaryContainer = Color(0xFF2D2640),
    onTertiaryContainer = Color(0xFFEDECEE),
    background = Color(0xFF0D0B14),
    onBackground = Color(0xFFEDECEE),
    surface = Color(0xFF0D0B14),
    onSurface = Color(0xFFEDECEE),
    surfaceVariant = Color(0xFF1A1426),
    onSurfaceVariant = Color(0xFF8B869E),
    surfaceTint = Color(0xFFA277FF),
    surfaceBright = Color(0xFF2D2640),
    surfaceDim = Color(0xFF0D0B14),
    surfaceContainerLowest = Color(0xFF000000),
    surfaceContainerLow = Color(0xFF000000),
    surfaceContainer = Color(0xFF0D0B14),
    surfaceContainerHigh = Color(0xFF1A1426),
    surfaceContainerHighest = Color(0xFF2D2640),
    outline = Color(0xFF8B869E),
    outlineVariant = Color(0xFF2D2640),
    error = Color(0xFFFF6767),
    onError = Color(0xFF0A0A0A),
    errorContainer = Color(0xFF3D1A24),
    onErrorContainer = Color(0xFFFFD6D6),
    inverseSurface = Color(0xFFEDECEE),
    inverseOnSurface = Color(0xFF0D0B14),
    scrim = Color(0xFF000000),
)

val BlackVioletLight: ColorScheme = lightColorScheme(
    primary = Color(0xFF6F4BB8),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFE8E2F5),
    onPrimaryContainer = Color(0xFF2D2640),
    inversePrimary = Color(0xFFA277FF),
    secondary = Color(0xFF4A4062),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFEAE3F7),
    onSecondaryContainer = Color(0xFF2D2640),
    tertiary = Color(0xFF8B5CF6),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFFEAE3F7),
    onTertiaryContainer = Color(0xFF2D2640),
    background = Color(0xFFFBF9FD),
    onBackground = Color(0xFF2D2640),
    surface = Color(0xFFFBF9FD),
    onSurface = Color(0xFF2D2640),
    surfaceVariant = Color(0xFFEAE3F7),
    onSurfaceVariant = Color(0xFF4A4062),
    surfaceTint = Color(0xFF6F4BB8),
    surfaceBright = Color(0xFFFFFFFF),
    surfaceDim = Color(0xFFE2D8F5),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFF5F2FA),
    surfaceContainer = Color(0xFFF5F2FA),
    surfaceContainerHigh = Color(0xFFEAE3F7),
    surfaceContainerHighest = Color(0xFFE8E2F5),
    outline = Color(0xFF8A80A0),
    outlineVariant = Color(0xFFE2D8F5),
    error = Color(0xFFB3261E),
    onError = Color(0xFFFFFFFF),
    errorContainer = Color(0xFFF9DEDC),
    onErrorContainer = Color(0xFF410E0B),
    inverseSurface = Color(0xFF2D2640),
    inverseOnSurface = Color(0xFFFBF9FD),
    scrim = Color(0xFF000000),
)

/**
 * Syntax paint from the desktop theme's `syntax` table, as ARGB. Null for roles
 * the theme doesn't set, which keep Zeron's neutrals.
 */
internal fun blackVioletSyntax(role: ColorRole, dark: Boolean): Long? {
    fun pick(darkHex: Long, lightHex: Long) = if (dark) darkHex else lightHex
    return when (role) {
        ColorRole.SYNTAX_KEYWORD, ColorRole.SYNTAX_TAG -> 0xFF7C5CFF
        ColorRole.SYNTAX_STRING -> pick(0xFFC4A5FF, 0xFF6F4BB8)
        ColorRole.SYNTAX_COMMENT -> pick(0xFF6E6580, 0xFF8A80A0)
        ColorRole.SYNTAX_NUMBER, ColorRole.SYNTAX_CONSTANT, ColorRole.SYNTAX_TYPE -> pick(0xFFC4A5FF, 0xFF8B5CF6)
        ColorRole.SYNTAX_FUNCTION -> pick(0xFFC4A5FF, 0xFF6F4BB8)
        ColorRole.SYNTAX_VARIABLE -> pick(0xFFEDECEE, 0xFF2D2640)
        ColorRole.SYNTAX_PROPERTY -> pick(0xFFC9C5D6, 0xFF4A4062)
        ColorRole.SYNTAX_OPERATOR -> pick(0xFF8B7CF6, 0xFF5B43E8)
        ColorRole.SYNTAX_PUNCTUATION -> pick(0xFFC9C5D6, 0xFF6F6A7A)
        ColorRole.SYNTAX_ATTRIBUTE -> pick(0xFFA277FF, 0xFF6F4BB8)
        ColorRole.SYNTAX_ESCAPE -> pick(0xFF22D3EE, 0xFF0E7490)
        else -> null
    }
}
