import 'package:flutter/material.dart';
import '../data/repo.dart';
import '../theme.dart';
import 'fx.dart';
import 'widgets.dart';

const termsVersion = '2026-10';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});
  Widget h(String t) => Padding(padding: const EdgeInsets.only(top: 18, bottom: 6), child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.ink)));
  Widget p(String t) => Text(t, style: const TextStyle(fontSize: 15, color: C.muted, height: 1.45));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Conditions et confidentialité', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF1EC), borderRadius: BorderRadius.circular(14)),
            child: const Text('Version provisoire (octobre 2026) : ce texte résume le fonctionnement de HAITIKET et doit être validé par un juriste avant le lancement commercial.', style: TextStyle(color: C.terracotta, fontWeight: FontWeight.w700)),
          ),
          h("Conditions d'utilisation"),
          p("HAITIKET met en relation des acheteurs, des vendeurs (boutiques professionnelles et particuliers du Bazar) et des livreurs en Haïti. Vous vous engagez à fournir des informations exactes, à ne proposer que des articles autorisés et à respecter les autres utilisateurs."),
          h('Tarifs'),
          p("Annonce Bazar : 2 USD pour 14 jours, renouvelable ; sans renouvellement l'annonce est bloquée puis supprimée après 30 jours. Boutique professionnelle : 20 USD par mois. Commission de 2 % sur les ventes. Les frais de livraison sont affichés avant la confirmation de la commande."),
          h('Paiements'),
          p("Les paiements sont traités par un prestataire externe (MonCash via Bazik). Une commande n'est confirmée que lorsque le prestataire confirme le paiement. Les remboursements sont exécutés après examen et ne sont déclarés effectués qu'une fois réellement versés."),
          h('Litiges'),
          p("Vous pouvez annuler une commande payée tant que le vendeur ne l'a pas confirmée. Ensuite, utilisez « Signaler un problème » : un administrateur examine le dossier et motive sa décision."),
          h('Politique de confidentialité'),
          p("Données collectées : nom, e-mail, téléphone, commune, adresses de livraison, photos que vous publiez, messages liés aux commandes, et votre position uniquement si vous l'autorisez."),
          p("Finalités : gérer votre compte, traiter vos commandes et paiements, organiser les livraisons, prévenir la fraude et vous assister."),
          p("Partage : votre adresse et votre téléphone ne sont transmis qu'aux personnes nécessaires à une commande (vendeur, livreur). Les paiements sont traités par notre prestataire. Nous ne vendons pas vos données."),
          p("Conservation : les données de commande et les écritures comptables sont conservées sans données personnelles après suppression du compte, pour respecter les obligations comptables et traiter d'éventuels litiges."),
          p("Vos droits : accéder à vos données, les corriger depuis « Mon profil », et supprimer votre compte à tout moment depuis « Mon profil » (impossible tant qu'une commande ou une livraison est en cours)."),
          const SizedBox(height: 30),
        ]),
      );
}

/// Connexion et inscription complète.
class AuthPanel extends StatefulWidget {
  final VoidCallback onChanged;
  const AuthPanel({super.key, required this.onChanged});
  @override
  State<AuthPanel> createState() => _AuthPanelState();
}

class _AuthPanelState extends State<AuthPanel> {
  bool signup = false, busy = false, accepted = false, hide = true;
  final first = TextEditingController(), last = TextEditingController(), phone = TextEditingController(), city = TextEditingController();
  final email = TextEditingController(), pass = TextEditingController(), pass2 = TextEditingController(), ref = TextEditingController();

  Future<void> submit() async {
    final e = email.text.trim();
    if (!e.contains('@') || !e.contains('.')) return toast(context, 'Adresse e-mail invalide.');
    if (pass.text.length < 8) return toast(context, 'Le mot de passe doit contenir au moins 8 caractères.');
    if (signup) {
      if (first.text.trim().length < 2 || last.text.trim().length < 2) return toast(context, 'Prénom et nom requis.');
      if (phone.text.replaceAll(RegExp(r'[^0-9]'), '').length < 8) return toast(context, 'Numéro de téléphone invalide.');
      if (pass.text != pass2.text) return toast(context, 'Les deux mots de passe ne correspondent pas.');
      if (!accepted) return toast(context, 'Vous devez accepter les conditions et la politique de confidentialité.');
    }
    setState(() => busy = true);
    try {
      if (signup) {
        final needsConfirm = await Repo.signUpFull(
          email: e,
          password: pass.text,
          fullName: '${first.text.trim()} ${last.text.trim()}',
          phone: phone.text.trim(),
          city: city.text.trim(),
          referral: ref.text.trim(),
        );
        if (mounted && needsConfirm) {
          await showDialog<void>(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text('Vérifiez votre e-mail'),
              content: Text('Un message de confirmation a été envoyé à $e. Ouvrez le lien qu\'il contient, puis revenez vous connecter.'),
              actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
            ),
          );
          if (mounted) setState(() => signup = false);
        }
      } else {
        await Repo.signIn(e, pass.text);
      }
      widget.onChanged();
    } catch (err) {
      if (mounted) toast(context, Repo.err(err));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> forgot() async {
    final e = email.text.trim();
    if (!e.contains('@')) return toast(context, "Saisissez d'abord votre adresse e-mail.");
    try {
      await Repo.resetPassword(e);
      if (mounted) toast(context, 'Si ce compte existe, un e-mail de réinitialisation vient d\'être envoyé.');
    } catch (err) {
      if (mounted) toast(context, Repo.err(err));
    }
  }

  Widget tab(String label, bool value) => Expanded(
        child: Pressable(
          onTap: () => setState(() => signup = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: signup == value ? C.ink : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
            child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: signup == value ? Colors.white : C.ink)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [tab('Se connecter', false), const SizedBox(width: 10), tab('Créer un compte', true)]),
        const SizedBox(height: 18),
        if (signup) ...[
          Row(children: [Expanded(child: Field(first, 'Prénom')), const SizedBox(width: 10), Expanded(child: Field(last, 'Nom'))]),
          Field(phone, 'Téléphone (ex. +509 3xxx xxxx)', type: TextInputType.phone),
          Field(city, 'Commune ou ville (ex. Delmas)'),
        ],
        Field(email, 'E-mail', type: TextInputType.emailAddress),
        TextField(
          controller: pass,
          obscureText: hide,
          decoration: InputDecoration(labelText: 'Mot de passe (8 caractères minimum)', suffixIcon: IconButton(icon: Icon(hide ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => hide = !hide))),
        ),
        const SizedBox(height: 12),
        if (signup) ...[
          Field(pass2, 'Confirmer le mot de passe', obscure: true),
          Field(ref, 'Code de parrainage (facultatif)'),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: accepted,
            onChanged: (v) => setState(() => accepted = v ?? false),
            title: const Text("J'accepte les conditions d'utilisation et la politique de confidentialité", style: TextStyle(fontSize: 14)),
            subtitle: GestureDetector(onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LegalScreen())), child: const Text('Lire le texte', style: TextStyle(color: C.green, fontWeight: FontWeight.w800, decoration: TextDecoration.underline))),
          ),
        ] else
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: forgot, child: const Text('Mot de passe oublié ?'))),
        const SizedBox(height: 10),
        PrimaryButton(label: busy ? 'Patientez…' : (signup ? 'Créer mon compte' : 'Me connecter'), icon: signup ? Icons.person_add_alt : Icons.login, onPressed: busy ? null : submit),
      ]);
}

/// Nouveau mot de passe après un lien de réinitialisation reçu par e-mail.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  State<ResetPasswordScreen> createState() => _ResetState();
}

class _ResetState extends State<ResetPasswordScreen> {
  final a = TextEditingController(), b = TextEditingController();
  bool busy = false;

  Future<void> save() async {
    if (a.text.length < 8) return toast(context, '8 caractères minimum.');
    if (a.text != b.text) return toast(context, 'Les deux mots de passe ne correspondent pas.');
    setState(() => busy = true);
    try {
      await Repo.updatePassword(a.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      toast(context, 'Mot de passe modifié.');
    } catch (e) {
      if (mounted) toast(context, Repo.err(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Nouveau mot de passe', style: TextStyle(fontWeight: FontWeight.w800, color: C.ink))),
        body: ListView(padding: const EdgeInsets.all(18), children: [
          Field(a, 'Nouveau mot de passe', obscure: true),
          Field(b, 'Confirmer le mot de passe', obscure: true),
          PrimaryButton(label: busy ? 'Enregistrement…' : 'Enregistrer', icon: Icons.lock_reset, onPressed: busy ? null : save),
        ]),
      );
}
