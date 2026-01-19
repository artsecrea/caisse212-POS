# i18n Quick Reference

## Quick Usage

### Import
```dart
import '../../utils/app_localizations.dart';
```

### Get Translations
```dart
final l10n = AppLocalizations.of(context)!;
Text(l10n.translate('key_name'))
```

## Common Translation Keys

### Actions
| Key | English | Arabic | French |
|-----|---------|--------|--------|
| `save` | Save | حفظ | Enregistrer |
| `cancel` | Cancel | إلغاء | Annuler |
| `delete` | Delete | حذف | Supprimer |
| `edit` | Edit | تعديل | Modifier |
| `add` | Add | إضافة | Ajouter |
| `search` | Search | بحث | Rechercher |
| `refresh` | Refresh | تحديث | Actualiser |

### Login
| Key | English | Arabic | French |
|-----|---------|--------|--------|
| `login` | Login | تسجيل الدخول | Connexion |
| `logout` | Logout | تسجيل الخروج | Déconnexion |
| `username` | Username | اسم المستخدم | Nom d'utilisateur |
| `password` | Password | كلمة المرور | Mot de passe |
| `sign_in` | Sign In | دخول | Se connecter |

### Orders
| Key | English | Arabic | French |
|-----|---------|--------|--------|
| `orders` | Orders | الطلبات | Commandes |
| `order_id` | Order ID | رقم الطلب | Numéro de commande |
| `pending` | Pending | قيد الانتظار | En attente |
| `completed` | Completed | مكتمل | Terminé |
| `dine_in` | Dine In | تناول في المكان | Sur place |
| `take_away` | Take Away | وجبات جاهزة | À emporter |

### Products
| Key | English | Arabic | French |
|-----|---------|--------|--------|
| `products` | Products | المنتجات | Produits |
| `quantity` | Quantity | الكمية | Quantité |
| `price` | Price | السعر | Prix |
| `category` | Category | الفئة | Catégorie |

### Payment
| Key | English | Arabic | French |
|-----|---------|--------|--------|
| `payment` | Payment | الدفع | Paiement |
| `cash` | Cash | نقداً | Espèces |
| `card` | Card | بطاقة | Carte |
| `total` | Total | الإجمالي | Total |

## Language Codes
- English: `en`
- Arabic: `ar`
- French: `fr`

## Change Language Programmatically
```dart
final settingsNotifier = ref.read(settingsProvider.notifier);
await settingsNotifier.setLanguage('ar'); // Arabic
```

## Change Language from UI
Settings → Appearance → Language → Select desired language

## Full List of Keys
See `lib/utils/app_localizations.dart` for complete list of available translation keys.

