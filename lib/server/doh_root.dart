/// Racine « SSL.com Root Certification Authority ECC », au bout de la chaîne
/// que servent 1.1.1.1 et 1.0.0.1 pour `cloudflare-dns.com` (relevé du
/// 2026-11-12 : feuille ← « SSL.com SSL Intermediate CA ECC R2 » ← cette
/// racine). Sous Windows, elle n'entre dans le magasin du système qu'au
/// premier téléchargement déclenché par Windows lui-même, ce que Dart ne
/// fait pas : sur un PC neuf, la connexion DoH échouait.
///
/// - Origine : http://www.ssl.com/repository/SSLcom-RootCA-ECC-384-R1.crt
///   (adresse donnée par l'intermédiaire), identique à celle de la liste de
///   Mozilla (https://curl.se/ca/cacert.pem).
/// - SHA-256 : 34:17:BB:06:CC:60:07:DA:1B:96:1C:92:0B:8A:B4:CE:
///   3F:AD:82:0E:4A:A3:0B:9A:CB:C4:A7:4E:BD:CE:BC:65
/// - Expire le 2041-02-12.
///
/// Renouveler : relever la chaîne
/// (`openssl s_client -connect 1.1.1.1:443 -servername cloudflare-dns.com
/// -showcerts`), prendre la racine indiquée par l'intermédiaire, recouper son
/// empreinte avec la liste de Mozilla, remplacer ce bloc, lancer le test
/// réseau de `test/server/cloudflare_dns_test.dart`. Si Cloudflare change
/// d'autorité, les racines du système prennent le relais (elles restent
/// chargées) ; ajouter la nouvelle racine ici, sans retirer l'ancienne tant
/// qu'elle est servie.
const sslComRootEcc = '''
-----BEGIN CERTIFICATE-----
MIICjTCCAhSgAwIBAgIIdebfy8FoW6gwCgYIKoZIzj0EAwIwfDELMAkGA1UEBhMC
VVMxDjAMBgNVBAgMBVRleGFzMRAwDgYDVQQHDAdIb3VzdG9uMRgwFgYDVQQKDA9T
U0wgQ29ycG9yYXRpb24xMTAvBgNVBAMMKFNTTC5jb20gUm9vdCBDZXJ0aWZpY2F0
aW9uIEF1dGhvcml0eSBFQ0MwHhcNMTYwMjEyMTgxNDAzWhcNNDEwMjEyMTgxNDAz
WjB8MQswCQYDVQQGEwJVUzEOMAwGA1UECAwFVGV4YXMxEDAOBgNVBAcMB0hvdXN0
b24xGDAWBgNVBAoMD1NTTCBDb3Jwb3JhdGlvbjExMC8GA1UEAwwoU1NMLmNvbSBS
b290IENlcnRpZmljYXRpb24gQXV0aG9yaXR5IEVDQzB2MBAGByqGSM49AgEGBSuB
BAAiA2IABEVuqVDEpiM2nl8ojRfLliJkP9x6jh3MCLOicSS6jkm5BBtHllirLZXI
7Z4INcgn64mMU1jrYor+8FsPazFSY0E7ic3s7LaNGdM0B9y7xgZ/wkWV7Mt/qCPg
CemB+vNH06NjMGEwHQYDVR0OBBYEFILRhXMw5zUE044CkvvlpNHEIejNMA8GA1Ud
EwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAUgtGFczDnNQTTjgKS++Wk0cQh6M0wDgYD
VR0PAQH/BAQDAgGGMAoGCCqGSM49BAMCA2cAMGQCMG/n61kRpGDPYbCWe+0F+S8T
kdzt5fxQaxFGRrMcIQBiu77D5+jNB5n5DQtdcj7EqgIwH7y6C+IwJPt8bYBVCpk+
gA0z5Wajs6O7pdWLjwkspl1+4vAHCGht0nxpbl/f5Wpl
-----END CERTIFICATE-----
''';
