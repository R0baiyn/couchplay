import 'dart:convert';
import 'dart:io';

// Racines de confiance ajoutées à celles du système, pour deux usages :
// - les connexions de la mise à jour (`Updater.context`) ;
// - toute connexion de l'app créée sans contexte TLS (affiches, API du
//   serveur, téléchargements), par `CloudflareHttpOverrides`.
//
// Chaînes que GitHub sert aux connexions de la mise à jour (relevé du
// 2026-11-24) :
// - `api.github.com`, `github.com` : feuille ← « Sectigo DV E36 » ←
//   « Sectigo Root E46 » ← [userTrustEcc] ;
// - `release-assets.githubusercontent.com`, `objects.githubusercontent.com`
//   (téléchargement des fichiers) : feuille ← « Let's Encrypt YR1 » ←
//   « Root YR » ← [isrgRootX1].
// Sous Windows, une racine n'entre dans le magasin du système qu'au premier
// téléchargement déclenché par Windows lui-même, ce que Dart ne fait pas :
// sur un PC sans USERTrust ECC, la vérification des mises à jour échouait
// (`CERTIFICATE_VERIFY_FAILED`), comme la connexion DoH (`doh_root.dart`).
//
// Origine des deux blocs : liste de Mozilla (https://curl.se/ca/cacert.pem,
// « Certificate data from Mozilla as of: Thu Nov 5 04:12:01 2026 GMT »),
// octet pour octet identiques aux certificats du magasin Windows
// (`Cert:\LocalMachine\Root`) d'un PC qui les a.
//
// Renouveler : relever les chaînes (`openssl s_client -connect
// api.github.com:443 -showcerts`, idem pour les trois autres hôtes), prendre
// la racine indiquée par le dernier intermédiaire, recouper son empreinte
// avec la liste de Mozilla, ajouter le bloc ici, mettre à jour l'empreinte
// attendue de `test/trusted_roots_test.dart` et lancer son groupe
// réseau (`RESEAU=1`). Les racines du système restent chargées : si GitHub
// change d'autorité, elles prennent le relais. Ne retirer une racine que
// lorsqu'elle n'est plus servie.

/// « USERTrust ECC Certification Authority ».
///
/// - SHA-256 : 4F:F4:60:D5:4B:9C:86:DA:BF:BC:FC:57:12:E0:40:0D:
///   2B:ED:3F:BC:4D:4F:BD:AA:86:E0:6A:DC:D2:A9:AD:7A
/// - SHA-1 : D1:CB:CA:5D:B2:D5:2A:7F:69:3B:67:4D:E5:F0:5A:1D:0C:95:7D:F0
/// - Expire le 2038-01-18.
const userTrustEcc = '''
-----BEGIN CERTIFICATE-----
MIICjzCCAhWgAwIBAgIQXIuZxVqUxdJxVt7NiYDMJjAKBggqhkjOPQQDAzCBiDELMAkGA1UEBhMC
VVMxEzARBgNVBAgTCk5ldyBKZXJzZXkxFDASBgNVBAcTC0plcnNleSBDaXR5MR4wHAYDVQQKExVU
aGUgVVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNVBAMTJVVTRVJUcnVzdCBFQ0MgQ2VydGlmaWNhdGlv
biBBdXRob3JpdHkwHhcNMTAwMjAxMDAwMDAwWhcNMzgwMTE4MjM1OTU5WjCBiDELMAkGA1UEBhMC
VVMxEzARBgNVBAgTCk5ldyBKZXJzZXkxFDASBgNVBAcTC0plcnNleSBDaXR5MR4wHAYDVQQKExVU
aGUgVVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNVBAMTJVVTRVJUcnVzdCBFQ0MgQ2VydGlmaWNhdGlv
biBBdXRob3JpdHkwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAAQarFRaqfloI+d61SRvU8Za2EurxtW2
0eZzca7dnNYMYf3boIkDuAUU7FfO7l0/4iGzzvfUinngo4N+LZfQYcTxmdwlkWOrfzCjtHDix6Ez
nPO/LlxTsV+zfTJ/ijTjeXmjQjBAMB0GA1UdDgQWBBQ64QmG1M8ZwpZ2dEl23OA1xmNjmjAOBgNV
HQ8BAf8EBAMCAQYwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAwNoADBlAjA2Z6EWCNzklwBB
HU6+4WMBzzuqQhFkoJ2UOQIReVx7Hfpkue4WQrO/isIJxOzksU0CMQDpKmFHjFJKS04YcPbWRNZu
9YO6bVi9JNlWSOrvxKJGgYhqOkbRqZtNyWHa0V1Xahg=
-----END CERTIFICATE-----
''';

/// « ISRG Root X1 ».
///
/// - SHA-256 : 96:BC:EC:06:26:49:76:F3:74:60:77:9A:CF:28:C5:A7:
///   CF:E8:A3:C0:AA:E1:1A:8F:FC:EE:05:C0:BD:DF:08:C6
/// - SHA-1 : CA:BD:2A:79:A1:07:6A:31:F2:1D:25:36:35:CB:03:9D:43:29:A5:E8
/// - Expire le 2035-06-04.
const isrgRootX1 = '''
-----BEGIN CERTIFICATE-----
MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAwTzELMAkGA1UE
BhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2VhcmNoIEdyb3VwMRUwEwYDVQQD
EwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4WhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQG
EwJVUzEpMCcGA1UEChMgSW50ZXJuZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMT
DElTUkcgUm9vdCBYMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54r
Vygch77ct984kIxuPOZXoHj3dcKi/vVqbvYATyjb3miGbESTtrFj/RQSa78f0uoxmyF+0TM8ukj1
3Xnfs7j/EvEhmkvBioZxaUpmZmyPfjxwv60pIgbz5MDmgK7iS4+3mX6UA5/TR5d8mUgjU+g4rk8K
b4Mu0UlXjIB0ttov0DiNewNwIRt18jA8+o+u3dpjq+sWT8KOEUt+zwvo/7V3LvSye0rgTBIlDHCN
Aymg4VMk7BPZ7hm/ELNKjD+Jo2FR3qyHB5T0Y3HsLuJvW5iB4YlcNHlsdu87kGJ55tukmi8mxdAQ
4Q7e2RCOFvu396j3x+UCB5iPNgiV5+I3lg02dZ77DnKxHZu8A/lJBdiB3QW0KtZB6awBdpUKD9jf
1b0SHzUvKBds0pjBqAlkd25HN7rOrFleaJ1/ctaJxQZBKT5ZPt0m9STJEadao0xAH0ahmbWnOlFu
hjuefXKnEgV4We0+UXgVCwOPjdAvBbI+e0ocS3MFEvzG6uBQE3xDk3SzynTnjh8BCNAw1FtxNrQH
usEwMFxIt4I7mKZ9YIqioymCzLq9gwQbooMDQaHWBfEbwrbwqHyGO0aoSCqI3Haadr8faqU9GY/r
OPNk3sgrDQoo//fb4hVC1CLQJ13hef4Y53CIrU7m2Ys6xt0nUW7/vGT1M0NPAgMBAAGjQjBAMA4G
A1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBR5tFnme7bl5AFzgAiIyBpY
9umbbjANBgkqhkiG9w0BAQsFAAOCAgEAVR9YqbyyqFDQDLHYGmkgJykIrGF1XIpu+ILlaS/V9lZL
ubhzEFnTIZd+50xx+7LSYK05qAvqFyFWhfFQDlnrzuBZ6brJFe+GnY+EgPbk6ZGQ3BebYhtF8GaV
0nxvwuo77x/Py9auJ/GpsMiu/X1+mvoiBOv/2X/qkSsisRcOj/KKNFtY2PwByVS5uCbMiogziUwt
hDyC3+6WVwW6LLv3xLfHTjuCvjHIInNzktHCgKQ5ORAzI4JMPJ+GslWYHb4phowim57iaztXOoJw
TdwJx4nLCgdNbOhdjsnvzqvHu7UrTkXWStAmzOVyyghqpZXjFaH3pO3JLF+l+/+sKAIuvtd7u+Nx
e5AW0wdeRlN8NwdCjNPElpzVmbUq4JUagEiuTDkHzsxHpFKVK7q4+63SM1N95R1NbdWhscdCb+ZA
JzVcoyi3B43njTOQ5yOf+1CceWxG1bQVs5ZufpsMljq4Ui0/1lvh+wjChP4kqKOJ2qxq4RgqsahD
YVvTH9w7jXbyLeiNdd8XM2w9U/t7y0Ff/9yi0GE44Za4rF2LN9d11TPAmRGunUHBcnWEvgJBQl9n
JEiU0Zsnvgc/ubhPgXRR4Xq37Z0j4r7g1SgEEzwxA57demyPxgcYxn/eR44/KJ4EBs+lVDR3veyJ
m+kXQ99b21/+jh5Xos1AnX5iItreGCc=
-----END CERTIFICATE-----
''';

/// Contexte TLS avec les racines du système plus [userTrustEcc] et
/// [isrgRootX1]. Seulement des racines en plus : la vérification du
/// certificat reste entière.
SecurityContext trustedContext({bool withTrustedRoots = true}) =>
    SecurityContext(withTrustedRoots: withTrustedRoots)
      ..setTrustedCertificatesBytes(utf8.encode(userTrustEcc))
      ..setTrustedCertificatesBytes(utf8.encode(isrgRootX1));

/// Le [trustedContext] de l'app : un seul, chargé au premier usage (les PEM
/// sont lus à la création, jamais une fois par client).
final appContext = trustedContext();
