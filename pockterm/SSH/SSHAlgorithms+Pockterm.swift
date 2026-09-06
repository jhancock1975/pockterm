import Citadel
import Crypto
import NIOSSH

extension SSHAlgorithms {

    /// What pockterm offers on top of the algorithms swift-nio-ssh implements
    /// natively — Curve25519 and ECDSA host keys, curve25519 key exchange,
    /// AES-GCM.
    ///
    /// Citadel's default is an empty `SSHAlgorithms()`, and passing nothing is
    /// why pockterm used to refuse outright any server whose only host key is
    /// `ssh-rsa`, whose only key exchange is group 14, or whose only cipher is
    /// AES-CTR. That is most of the older estate — anything not kept current,
    /// and plenty of appliances and jump hosts that never will be.
    ///
    /// **These are legacy on purpose.** `ssh-rsa` signs with SHA-1, and so does
    /// `diffie-hellman-group14-sha1`; OpenSSH has both switched off by default
    /// in current releases. Citadel's `Modification.add` **appends**, so every
    /// one of them sits at the end of its preference list: a current server
    /// still negotiates current crypto, and these are reached only when the
    /// server offers nothing better. Nothing modern is displaced.
    ///
    /// Enumerated here rather than taken from Citadel's `SSHAlgorithms.all` so
    /// that what we are willing to negotiate is our decision, recorded, and
    /// cannot widen underneath us when Citadel moves.
    static let pockterm: SSHAlgorithms = {
        var algorithms = SSHAlgorithms()
        algorithms.transportProtectionSchemes = .add([
            AES128CTR.self,
        ])
        algorithms.keyExchangeAlgorithms = .add([
            DiffieHellmanGroup14Sha256.self,
            DiffieHellmanGroup14Sha1.self,
        ])
        // Spelled `publicKeyAlgorihtms` upstream. Not a typo here.
        algorithms.publicKeyAlgorihtms = .add([
            (Insecure.RSA.PublicKey.self, Insecure.RSA.Signature.self),
        ])
        return algorithms
    }()
}
