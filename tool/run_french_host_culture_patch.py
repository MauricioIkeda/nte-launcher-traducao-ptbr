from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
patcher = ROOT / "tool" / "implement_french_host_culture.py"
source = patcher.read_text(encoding="utf-8")
source = source.replace(
    "marker = \"\\n  test('rejects duplicated destinations', () {\\n\"",
    "marker = \"\\n  test('rejects duplicate file names case-insensitively', () {\\n\"",
)
start = source.index('    path = "test/receipt_repository_test.dart"')
end = source.index('    path = "test/installation_service_test.dart"', start)
corrected = r"""    path = "test/receipt_repository_test.dart"
    text = read(path)
    marker = "\n}\n\nFuture<InstallReceipt> _receipt(\n"
    test = r'''

  test('receipt keeps optional text-language rollback metadata', () async {
    final storage = await repository.storageFor(gameA.path);
    final receipt = await _receipt(
      repository,
      gameA.path,
      textLanguage: const TextLanguageReceipt(
        configPath: r'C:\Users\Test\AppData\Local\HT\Saved_Global\Config\Windows\GameUserSettings.ini',
        key: 'TextLanguage',
        previousRawValue: 'en',
        previousValue: 'en',
        requestedCulture: 'fr',
      ),
    );
    await repository.write(gameA.path, receipt);
    final read = (await repository.read(gameA.path)).receipt;
    expect(read?.textLanguage?.previousValue, 'en');
    expect(await storage.receipt.exists(), isTrue);
  });
'''
    text = once(
        text,
        marker,
        test + marker,
        "receipt language test",
    )
    text = once(
        text,
        "Future<InstallReceipt> _receipt(\n  ReceiptRepository repository,\n  String gameDirectory,\n) async {\n",
        "Future<InstallReceipt> _receipt(\n  ReceiptRepository repository,\n  String gameDirectory, {\n  TextLanguageReceipt? textLanguage,\n}) async {\n",
        "receipt helper signature",
    )
    text = once(
        text,
        "    manifestPublishedAt: DateTime.utc(2026, 7, 29),\n    files: const [\n",
        "    manifestPublishedAt: DateTime.utc(2026, 7, 29),\n    textLanguage: textLanguage,\n    files: const [\n",
        "receipt helper metadata",
    )
    write(path, text)

"""
source = source[:start] + corrected + source[end:]
namespace = {"__name__": "launcher_patch", "__file__": str(patcher)}
exec(compile(source, str(patcher), "exec"), namespace)
namespace["main"]()
