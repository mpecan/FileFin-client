/// If [text] claims to be WebVTT but is actually ASS/SSA, strips the bogus
/// `WEBVTT` header so libmpv can parse it as the ASS it is.
///
/// FileFin's subtitle conversion prepends `WEBVTT` even when the body is ASS
/// (`[Script Info]`, `[V4+ Styles]`, `Dialogue:` lines). libmpv trusts the
/// header and tries to parse as VTT, gets ASS content, and renders nothing.
/// Detecting the ASS body and stripping the header fixes it on the client
/// side; the real fix is server-side (the converter should not write `WEBVTT`
/// when the output format is ASS).
String repairSubtitle(String text) {
  if (text.startsWith('WEBVTT') && text.contains('[Script Info]')) {
    return text.replaceFirst('WEBVTT', '').trimLeft();
  }
  return text;
}
