# Steam Workshop page study (Project Zomboid), 2026-09-13

How the most subscribed Project Zomboid Workshop pages are written and laid out, read from the live pages. Structure claims below were checked against the raw HTML of each item description, not only against the rendered text, so the BBCode counts are exact.

Method note. The item IDs this study started from did not all match the mod names they were given with. The IDs resolve as follows: 2458631365 is Expanded Helicopter Events (not Superb Survivors), 2648779556 is True Actions Act 3 Dancing (not Act 1 Sitting), 2619072426 is Weapon Condition Indicator (not Autotsar Tuning Atelier), 2875848298 is Common Sense (not Snake's Traits). Two IDs could not be fetched at all: 2860193166 and 2713136832 both return the Steam error page "There was a problem accessing the item", both through a fetching tool and through a direct request. So the five pages studied are the five that returned content.

Steam renders BBCode into classed HTML (`bb_h1`, `bb_h2`, `bb_h3`, `bb_ul`, `bb_code`, `bb_hr`, `blockquote bb_blockquote`, `bb_table`, `bb_spoiler`). Counting those classes tells us which tags the author actually typed.

## Common Sense (BB_CommonSense, Braven)

- About 3,612,089 subscribers. 35 change notes. 8 screenshots plus 1 video attached to the item.
- Block order: title banner image, three-line pitch, features banner image, bulleted feature list, FAQ banner image, five FAQ entries, credits banner image, a "like and favourite" animated image, a "Like my mods?" block, three link banner images (Ko-fi, Discord, YouTube), then the licence block, then Workshop ID and Mod ID.
- Hook is one plain line, no header tag: "It's something so simple, but PZ lacks it sometimes." Then two lines of pitch, including "I plan to continuously update this mod, adding more and more common sense to the game over time."
- The feature list is deliberately partial and says so: "Here is a summary of what the mod can do. Keep in mind there is MUCH more than this!" and ends with "...And much more!" linked to a Workshop discussion thread.
- 9 images embedded inside the description, 8 item screenshots attached separately. The embedded images are not screenshots. They are 4 title and section banners, 2 small animated GIFs, and 3 link buttons. Hosted on i.ibb.co and i.postimg.cc.
- BBCode actually used: 6 `[h1]`, 1 `[list]` with 8 `[*]` items, 13 `[b]`, 1 `[code]`, 10 links, 9 `[img]`. No `[hr]`, no `[table]`, no `[spoiler]`, no `[quote]`.
- The five FAQ questions are each an `[h1]`, with the answer as plain text on the next line. That is the cheapest possible FAQ and it reads well: "Does it work in the Latest Build?" / "Right out of the box!"
- Present: FAQ yes, compatibility yes but as one line plus a link to a discussion thread of known conflicts, known issues no, roadmap no (only the "I plan to continuously update" line), changelog no in-description (35 change notes exist as the Steam feature), credits yes ("Powered by BitBraven. Expanded Prying Mechanic commissioned by Rokko."), translation call no, donation yes (Ko-fi, Patreon mentioned), Discord yes, GitHub no, rate and favourite yes but delivered as an image not as text, do-not-reupload yes, Mod ID yes, sandbox note no, dependencies no.
- The licence sits in a `[code]` block, which renders as a fixed-width grey box: "This product is protected under copyright law. You are free to use it for personal purposes. Redistribution, for commercial purposes or not, is strictly prohibited without prior permission." It links out to a full EULA PDF.
- About 308 words. No ALL CAPS headers, because the headers are banner images. One heart emoji at the very end. Nothing centred.
- Reads professional because of the banner set: four banners in one visual family give the page a spine, and the body text stays short. Reads slightly amateur because the real feature list lives in a forum thread and the page carries two decorative GIFs.

## Weapon Condition Indicator (TheStar, NoctisFalco)

- About 3,749,981 subscribers. 20 change notes. 4 screenshots plus 1 video attached.
- Block order: one-paragraph pitch with no header, `[h2] Features` with a dash list, `[h2] Options`, `[h2] Requirements`, `[h2] Compatibility`, translation credit line, support appeal, an animated GIF of the mod in action, three support buttons, a "My other mods" row of seven thumbnails, a quoted notice, a permissions block, then Workshop ID and Mod ID.
- This is the most text-first page of the five. The first sentence is functional, not dramatic: "The mod shows condition (durability) of a weapon attached to the hotbar (back, belt, holster, etc.) or equipped in the primary hand. And many other useful features."
- 11 images embedded in the description, 4 screenshots attached. The single demo GIF is the only image that shows the mod; the other 10 are buttons and mod thumbnails. Hosted on i.imgur.com.
- BBCode actually used: 4 `[h2]`, 5 `[b]`, 1 `[i]`, 1 `[quote]`, 16 links, 11 `[img]`. No `[list]` tag at all. The feature list is six lines each starting with a hyphen and ending with a semicolon, which is a hand-rolled list.
- Requirements is explicit and short: "Game version: Build 41.60+ (MP supported)" then "Mod Options is required for this mod to work" with the dependency linked.
- Compatibility is one honest sentence naming the files it overrides: "May conflict with other mods that override ISHotbar.lua and/or ISEquippedItem.lua."
- Options section tells the player the exact menu path: "Go to Options -> Mods -> Weapon Condition Indicator section."
- Present: FAQ no, compatibility yes as prose, known issues no, roadmap no, changelog no in-description, credits yes for the Chinese translation, translation call no but a translation is credited and linked, donation yes (Patreon, Ko-fi), Discord yes twice, GitHub no, rate and favourite no, do-not-reupload yes, Mod ID yes, sandbox note no but the mod options path is given, dependencies yes.
- About 289 words. Title-case headers, not ALL CAPS. Nothing centred. Two emoji used as icons before the Discord notice and the permissions header (a warning sign and a no-entry sign).
- Reads the most professional of the five. The reason is order: what it does, features, how to configure, what it needs, what it breaks. Everything a player asks in the comments is answered before the donation buttons appear.

## Expanded Helicopter Events (ExpandedHelicopterEvents, shark and Chuckleberry Finn)

- About 1,277,383 subscribers. 220 change notes, the highest of the five. 5 screenshots attached.
- Block order: `[h1]` one-line hook, `[h3]` framework note in italics, a status banner image, three banner buttons linked to GitHub (FAQ, FEATURES, GITHUB), `[h2] Check out the sub-mods:` with two poster thumbnails, `[h2] For a more varied looting experience, try these integrated mods:` with two named linked mods, a bug-hunt banner, three more GitHub and support banners, `[h3]` copyright line, then Workshop ID and Mod ID.
- The hook is the whole pitch and it is one sentence: "This mod replaces the vanilla helicopter event with a more dynamic suite of events which are both challenging and fair."
- 10 images embedded in the description, 5 screenshots attached. All 10 embedded images are banners or buttons. Every one is hosted on raw.githubusercontent.com out of the mod's own repository, so the author edits the image in git and the page updates.
- BBCode actually used: 1 `[h1]`, 3 `[h2]`, 2 `[h3]`, 2 `[b]`, 1 `[i]`, 20 links, 10 `[img]`. No lists, no `[hr]`, no `[quote]`, no `[code]`, no `[table]`.
- Only about 105 words of prose. This is the shortest description of the five by a wide margin. The documentation is not on Steam at all; it is on GitHub behind the FAQ and FEATURES buttons.
- Bug reports are routed deliberately: "The preferred method of reporting issues is through our github's issues page."
- Present: FAQ yes but off-site, compatibility no, known issues no, roadmap no, changelog no in-description, credits partial through the copyright line, translation call no, donation yes through a support banner, Discord no, GitHub yes and heavily, rate and favourite no, do-not-reupload yes ("This item is not authorized for posting on Steam, except under the Steam account named shark"), Mod ID yes, sandbox note no, dependencies yes but through Steam's own required-items box, not in the text (Easy Config Chucked).
- No ALL CAPS prose. The caps live inside the banner artwork. Nothing centred. No emoji.
- Reads professional because the page behaves like a landing page: hook, buttons, related products, support. Its weakness is that a player who will not click through learns almost nothing about the mod from the page itself.

## True Actions Act 3 Dancing (TrueActionsDancing, iBrRus)

- About 1,776,154 subscribers. 7 change notes. 4 screenshots plus 2 videos attached.
- Block order: Patreon banner at the very top, a flavour paragraph about dancing in primitive societies, the pitch written in-world as a magazine advertisement, a second in-world block advertising a fictional cereal, a product image, `[h1] FAQ:` with 7 question and answer pairs, `[h3] Credits:`, three support and site banners, a quoted server-use and permissions notice, a linked image, then Version, Workshop ID and Mod ID.
- The pitch is the most distinctive of the five because it never speaks as a mod author. It speaks as the magazine: "That is why we have published the magazine Dance. Explore 45 different dance moves by finding and reading the issues of our new magazine."
- 6 images embedded in the description, 4 screenshots attached. Notable: all 6 embedded images are hosted on steamuserimages-a.akamaihd.net, that is, they are images uploaded to Steam and then hotlinked back into the description. One of them is literally named "Like the mod.png". This proves the Steam-as-host technique in a live page.
- BBCode actually used: 1 `[h1]`, 1 `[h3]`, 7 `[b]`, 1 `[quote]`, 12 links, 6 `[img]`. No `[list]`: the FAQ questions are `[b]` lines with the answer on the line below.
- The FAQ is the page's real body, 7 pairs, and it answers exactly the things that generate comments: "Will the mod work if I add it to an existing save?" / "Yes, it will." and "How to dance?" / "Open the emotion menu (press and hold Q) and select the appropriate item."
- Present: FAQ yes, compatibility no, known issues no, roadmap no, changelog no in-description but a Version line is given ("Version:1.06"), credits yes, translation call no, donation yes (Patreon and Boosty), Discord yes twice, GitHub no, rate and favourite no in text but one embedded image asks for it, do-not-reupload yes and it also grants server use explicitly ("You can freely use this mod on your server"), Mod ID yes, sandbox note no, dependencies no.
- The permissions block links to The Indie Stone's own mod permission policy page, which is a nice touch of legitimacy.
- About 422 words, the longest of the five. No ALL CAPS. Nothing centred. No emoji.
- Reads professional in its mechanics (version number, FAQ, explicit server permission, link to the official policy) while the voice is playful. The lesson is that voice and rigour are independent.

## Brita's Weapon Pack (Brita)

- About 3,342,758 subscribers, the second highest of the five. 48 change notes. 26 screenshots plus 1 video attached, the largest gallery of the five.
- Block order: an `[h1]` status warning that the mod is broken on Build 42, a link to the official guide, an `[h1]` note about removed texture submods, an `[h1]` permissions and copyright warning, an `[h1] NOT COMPATIBLE WITH` list, an `[h1] KNOWN BUGS` list, a hotfix date, Patreon and Ko-fi links as bare URLs, then Workshop ID and Mod ID.
- There is no pitch at all. The page never says what the mod does. The first words are: "We are trying to fix the mod, no promises....Many of the work-around methods that allow the features of this mod to work have been shut-down and disabled by B42. ... It's FUBAR at the moment."
- 0 images embedded in the description. All 26 images are item screenshots attached to the item. This is the only page of the five that embeds nothing.
- BBCode actually used: 5 `[h1]`, 6 `[u]`, 3 links. No `[b]`, no `[list]`, no `[img]`, no `[hr]`, no `[quote]`, no `[code]`, no `[table]`. Sub-items are typed as lines starting with a hyphen, and emphasis is typed as runs of asterisks ("*** So both can be adjusted lower or higher **"), which renders as literal asterisks.
- Present: FAQ no, compatibility yes and it is the best of the five because it names the mod and the reason ("Real Full Auto Mod... it overrides code that already exists and WILL cause problems", "Snakes Mod... that is a full conversion, this is a full conversion"), known issues yes though the section is confusingly titled "KNOWN BUGS - THAT WERE FIXED BY LAST UPDATE", roadmap no, changelog no in-description, credits no, translation call no, donation yes as bare unlinked-looking URLs, Discord no, GitHub no, rate and favourite no, do-not-reupload yes and the most emphatic of the five ("Absolutely NO Permission is given under any circumstance to re-post or re-publish this mod"), Mod ID yes, sandbox note yes in effect (the damage multiplier ranges from 50% to 200% are described), dependencies yes through Steam's required-items box (Arsenal[26] GunFighter Mod).
- About 343 words. Heavy ALL CAPS, both for headers and inside sentences. Nothing centred. No emoji. Dashes and asterisks used as makeshift formatting.
- Reads the most amateur of the five despite being the second most subscribed. The subscriber count comes from the content, not the page. Useful as a counter-example: the page survives on reputation, and a new mod has none.

## Steam image and preview rules

Verified facts, each with the source I checked.

- Steam's own stylesheet caps description images at 630 pixels wide. Verified directly: `.workshopItemDescription img { max-width: 630px; }` in https://community.akamai.steamstatic.com/public/css/skin_1/workshop.css . So a banner wider than 630 px is scaled down in the browser and you are paying bytes for nothing. 630 px is the number to design to.
- `[img]` is not documented on Steam's own formatting help page. I fetched https://steamcommunity.com/comment/ForumTopic/formattinghelp and it lists `[h1] [h2] [h3] [b] [u] [i] [strike] [spoiler] [noparse] [hr] [url] [list] [olist] [quote] [code]` and does not mention `[img]` at all. `[img]` works anyway, proved by all four image-using pages above. Treat `[img]` as supported but undocumented.
- There is no centring tag in Steam BBCode. Confirmed by the absence of any centring tag on the formatting help page, and by the raw HTML of all five descriptions containing zero `text-align: center`. Pages that look centred are using wide banner images, not centred text.
- `[img]` needs a publicly reachable URL. The five pages use raw.githubusercontent.com, i.imgur.com, i.ibb.co, i.postimg.cc and Steam's own image host. No page references a file inside the uploaded mod content, and Steam exposes no public URL for files inside a Workshop item's payload, so hosting elsewhere is not a style choice, it is the only option.
- Item screenshots uploaded to Steam can be used as the host. Verified on True Actions Act 3, whose description embeds six images from `https://steamuserimages-a.akamaihd.net/ugc/<id>/<hash>/`. I ran a HEAD request on one of them and got `HTTP/2 200`, `content-type: image/png`, `content-disposition: inline; filename*=UTF-8''1679077836_Like the mod.png`. So the file was uploaded to Steam and hotlinked back in.
- How to get that direct URL. The current host is `images.steamusercontent.com`. On a live item page the main preview is served as `https://images.steamusercontent.com/ugc/<id>/<hash>/?imw=268&imh=268&ima=fit&impolicy=Letterbox&...`. Strip the whole query string and the bare `https://images.steamusercontent.com/ugc/<id>/<hash>/` returns the full-size original: verified `HTTP/1.1 200 OK`, `Content-Length: 99524`, `Content-Type: image/png`. Note that you cannot invent your own resize parameters: the same URL with `?imw=5000&imh=5000&ima=fit` returned `404 Not Found`, so only Steam's own parameter sets are honoured.
- Preview image formats and the 1 MB limit. From Valve's own API reference, https://partner.steamgames.com/doc/api/ISteamUGC : `SetItemPreview` says the format "should be one that both the web and the application (if necessary) can render. Suggested formats include JPG, PNG and GIF", and `AddItemPreviewFile` says the image "must be under 1MB". Preview images are stored in the user's Steam Cloud, which is why the app needs Cloud quota configured.
- GIFs work inside descriptions. Verified on two pages: Weapon Condition Indicator embeds `i.imgur.com/cKVBRWw.gif` as its demo, and Common Sense embeds two GIFs. So an animated demo can live in the description body.
- Steam adds `crossorigin="anonymous"` to description images from third-party hosts, and does not add it to images on its own UGC host. Observed in the raw HTML. Practical consequence: a host that refuses cross-origin requests or that blocks hotlinking can break the image, and the failure is silent for the reader.

Not verified, treat as folklore.

- The often-repeated "425 px in windowed mode, 627 px in full page" figures come from a community guide (https://steamcommunity.com/sharedfiles/filedetails/?id=812684948) about artwork showcases, not from Valve, and they do not match the 630 px I measured in Steam's stylesheet. Use 630 px.
- "Preview must be 512 x 512" is a community recommendation, repeated in several guides, with no Valve page behind it. Valve states a format suggestion and a 1 MB ceiling for additional previews, nothing about dimensions.
- Whether plain `http://` image URLs are rejected or silently rewritten: I found no Valve statement and no example in the sample, since all five pages use `https://`. Use `https://` and the question does not arise.
- The Steam guide at id 133329575, suggested as the BBCode reference, is not a formatting guide. It fetches as a removed Sonic Adventure DX screenshot. The real reference is the formatting help URL above.

## The common pattern

The block order that recurs, ignoring Brita's which has no pitch at all:

1. Title or logo banner image, full width, at the very top. Three of the four image-using pages open with one.
2. A single-sentence hook in plain text or one header tag. It names the change, not the mod. "This mod replaces the vanilla helicopter event with a more dynamic suite of events."
3. Two or three lines of pitch. What problem this fixes and the scope of it.
4. A section banner image or `[h2]` reading Features.
5. The feature list. Either `[list]` with `[b]` leads on the noun that matters, or hyphen lines. Six to eight items, never twenty, and it is fine to end with "and much more" pointing at a discussion thread.
6. One demo image or GIF placed after the feature list, showing the thing working.
7. Configuration, in one line, with the literal menu path the player must follow.
8. Requirements and dependencies, with each dependency linked, plus the game build it targets.
9. Compatibility, naming mods or files it conflicts with, in prose rather than a table.
10. FAQ. Four to eight question and answer pairs, question as `[h1]` or `[b]`, answer on the next line, one sentence each. The must-have question is always "does it work on an existing save".
11. Credits, including translators.
12. Support and links row: Ko-fi or Patreon, Discord, GitHub, as small linked banner images side by side.
13. Permissions and do-not-reupload notice, often in `[quote]` or `[code]` so it reads as fine print.
14. Workshop ID and Mod ID on the last two lines. All five pages end this way. It is the strongest convention in the whole sample.

What makes a page read professional:

- A consistent set of section banners in one visual family. This is the single biggest difference between the polished pages and Brita's. The banners do the work that ALL CAPS text tries and fails to do.
- Short prose. The most professional page in the sample is 289 words. Long is not thorough, it is unedited.
- Answering the comment-section questions before they are asked: existing saves, multiplayer, current build, conflicts. Each answer one sentence.
- Naming things precisely. "May conflict with other mods that override ISHotbar.lua" earns more trust than "should be compatible with everything".
- Giving the exact configuration path rather than saying the mod is configurable.
- Real BBCode instead of typed punctuation. Runs of asterisks and rows of hyphens read as a text file pasted into a web page.
- Emphasis used sparingly, on the nouns in a feature list. ALL CAPS inside sentences reads as shouting and is the clearest amateur tell in the sample.
- Ending with Mod ID and Workshop ID, and stating permissions plainly. Server admins look for exactly those lines, and their absence is noticed.
- Hosting the banners in the mod's own git repository, as Expanded Helicopter Events does, so the page artwork is versioned with the mod instead of sitting on a free image host that may expire.
