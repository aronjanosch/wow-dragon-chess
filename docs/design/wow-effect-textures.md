# Soft effect textures (candidates for ui/juice.lua)

As of 2026-10-05. Source: local community listfile (`~/.cache/dragon-chess/community-listfile.csv`, via `tools/wow_asset.sh`). The listfile only proves that the path exists somewhere in the game, NOT that it ships with the Classic client (Anniversary/Era). It also says nothing about the alpha format (grayscale vs. color, alpha channel). Everything except "known" has to be checked once in game (green square = missing).

Always use: `tex:SetTexture(path)`, `tex:SetBlendMode("ADD")`, `tex:SetVertexColor(r,g,b,a)`. Paths with `\\`; case-insensitive. All `.blp`.

| Role | Candidate | Path | FileDataID | Certainty | Usage |
|---|---|---|---|---|---|
| 1 Glow/spot | Generic Glow | `Spells\GenericGlow2b` | 166225 | Listfile, vanilla file name (ID 166xxx = original stock), widespread in addons (WeakAuras), but not verified by us | ADD, square, size 1.5-3x particle, alpha 0.6-1 |
| 1 Glow/spot | Generic Glow 64 | `Spells\GenericGlow64` | 166232 | Listfile, unverified | as above, fallback |
| 1 Glow/spot | White Glow | `Spells\White_Glow2` | 167205 | Listfile, unverified | white -> tintable to any color via VertexColor (preferred if grayscale) |
| 2 Sparkle, 4-point | star4 | `Interface\Cooldown\star4` | 131010 | KNOWN FOR SURE (cooldown flare, used in addons for years) | ADD, size 12-40px, optional SetRotation for twinkling |
| 2 Sparkle | starburst | `Interface\Cooldown\starburst` | 131011 | known (same directory, cooldown ping family) | ADD, large burst, scale-up + fade |
| 2 Sparkle | Flare | `Spells\T_VFX_FLARE05` / `Spells\Flare09` | 167035 / 166194 | Listfile, unverified (T_VFX_* more likely TBC+) | ADD |
| 3 Ring/Shockwave | ping4 | `Interface\Cooldown\ping4` | 131009 | KNOWN FOR SURE (soft ring pulse) | ADD, scale from small to 3-5x, alpha 1->0 |
| 3 Ring | Shockwave | `Spells\Shockwave4` / `Spells\Shockwave10` | 166863 / 166848 | Listfile, unverified | ADD, ring with gradient |
| 3 Ring | Minimap-Ping | `Interface\Minimap\Ping\ping2` (ping4/5/6 ebenfalls) | 136437 | Listfile, vanilla stock, probable | ADD, thin ring alternative |
| 3 Ring | Shock Ring Crescent | `Spells\ShockRingCrescent256` | 166847 | Listfile, unverified | half ring/arc, also usable for Cone |
| 4 Beam segment | Beam1 | `Spells\Beam1` | 165663 | Listfile, unverified | ADD, stretched horizontally (width = row, height 12-24px) |
| 4 Beam | Gradient Beam | `Spells\GradiantBeam_02` | 512410 | Listfile, late asset, risk for Classic | fallback only |
| 4 Beam | Moonbeam | `Spells\Moonbeam` | 166589 | Listfile, unverified | vertical beam, rotatable with SetRotation |
| 5 Lightning | Lightning2 / 4 | `Spells\Lightning2`, `Spells\Lightning4` | 166474 / 166481 | Listfile, vanilla file names, unverified | ADD, stretched, random height/SetRotation per segment; `_red`/`_purple` variants come pre-colored (`_black` for shadow) |
| 5 Lightning | Lightning1b_* | `Spells\Lightning1b_purple` | 166472 | Listfile, unverified | Variant |
| 6 Smoke/dust | Dust1_a | `Spells\Dust1_a` | 165971 | Listfile, unverified | normal blend (BLEND) or ADD with low alpha, scale 1->2.5 |
| 6 Smoke | SmokeFlat1 | `Spells\SmokeFlat1` | 166910 | Listfile, unverified | BLEND, landing ring: 4-6 pieces radially |
| 6 Smoke | Blobs | `Spells\Blobs` / `Spells\Blobs2` | 165717 / 165718 | Listfile, unverified | soft cloud, ADD low alpha |
| 7 Cone/Wedge | EnergyWedge_h | `Spells\EnergyWedge_h` | 240888 | Listfile (24xxxx = added later, Classic uncertain) | stretched + SetRotation |
| 7 Cone | Frost128ConeOfCold | `Spells\Frost128ConeOfCold` | 240903 | Listfile, unverified | bluish, cone |
| 7 Cone | GradientCrescent | `Spells\GradientCrescent` | 166268 | Listfile, vanilla ID | arc/fan approximation |

Honest assessment: only `Interface\Cooldown\star4`, `ping4`, `starburst` count as known. For glow, beam, lightning, smoke, cone there is no verified standard path; the `Spells\*` textures with IDs < 170000 come from the vanilla stock and are very likely present in the Era/Anniversary client, but check before building them in. Textures with ID >= 240000 are newer (risk). There is no clean wedge texture for Cone; fallback: `Spells\ShockRingCrescent256` or several rotated `GradientCrescent`, or the existing quad-fan solution. Fallback for everything: `Interface\Buttons\WHITE8X8` + ROUND_MASK (`Interface\CharacterFrame\TempPortraitAlphaMask`) gives a hard circle, not a soft glow.

## Check in game

`/dcprobe` has no effect-texture mode yet; for now run this one-liner in chat (no addon code needed):

```
/run local f=CreateFrame("Frame","DCFxTex",UIParent,"BackdropTemplate");f:SetSize(900,300);f:SetPoint("CENTER");f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"});f:SetBackdropColor(0,0,0,.9);local L={"Spells\\GenericGlow2b","Spells\\White_Glow2","Interface\\Cooldown\\star4","Interface\\Cooldown\\ping4","Spells\\Shockwave4","Spells\\Beam1","Spells\\Lightning2","Spells\\Dust1_a","Spells\\EnergyWedge_h"};for i,p in ipairs(L) do local t=f:CreateTexture();t:SetSize(90,90);t:SetPoint("TOPLEFT",10+(i-1)*98,-10);t:SetTexture(p);t:SetBlendMode("ADD");t:SetVertexColor(1,.6,.2);local s=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");s:SetPoint("TOP",t,"BOTTOM");s:SetWidth(95);s:SetText(p:match("[^\\]+$")) end
```

Reading it: green square/nothing = path missing in the client; hard rectangle = texture without alpha (unusable with ADD). For hits, enter the path in `ui/assets.lua` and test `Fx` via `/dcfx` or the debug panel (ui/debug.lua, effect buttons break/spawn/shot, Fx.DEV_DURATION = 6 s). Also run `C_Texture.GetFilenameFromFileDataID(id)` in chat against the FileDataID (it exists according to wow-forever-api.md) to confirm IDs. `texture:GetTexture()` after SetTexture is unreliable according to the probe.
