// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayOrderMeta = const VerificationMeta(
    'displayOrder',
  );
  @override
  late final GeneratedColumn<int> displayOrder = GeneratedColumn<int>(
    'display_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    imageUrl,
    description,
    displayOrder,
    isActive,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Category> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('display_order')) {
      context.handle(
        _displayOrderMeta,
        displayOrder.isAcceptableOrUnknown(
          data['display_order']!,
          _displayOrderMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      displayOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}display_order'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  final int id;
  final String name;
  final String? imageUrl;
  final String? description;
  final int displayOrder;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Category({
    required this.id,
    required this.name,
    this.imageUrl,
    this.description,
    required this.displayOrder,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['display_order'] = Variable<int>(displayOrder);
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      displayOrder: Value(displayOrder),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Category.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      description: serializer.fromJson<String?>(json['description']),
      displayOrder: serializer.fromJson<int>(json['displayOrder']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'description': serializer.toJson<String?>(description),
      'displayOrder': serializer.toJson<int>(displayOrder),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Category copyWith({
    int? id,
    String? name,
    Value<String?> imageUrl = const Value.absent(),
    Value<String?> description = const Value.absent(),
    int? displayOrder,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Category(
    id: id ?? this.id,
    name: name ?? this.name,
    imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
    description: description.present ? description.value : this.description,
    displayOrder: displayOrder ?? this.displayOrder,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      description: data.description.present
          ? data.description.value
          : this.description,
      displayOrder: data.displayOrder.present
          ? data.displayOrder.value
          : this.displayOrder,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('description: $description, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    imageUrl,
    description,
    displayOrder,
    isActive,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.name == this.name &&
          other.imageUrl == this.imageUrl &&
          other.description == this.description &&
          other.displayOrder == this.displayOrder &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> imageUrl;
  final Value<String?> description;
  final Value<int> displayOrder;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.description = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  CategoriesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.imageUrl = const Value.absent(),
    this.description = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Category> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? imageUrl,
    Expression<String>? description,
    Expression<int>? displayOrder,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (imageUrl != null) 'image_url': imageUrl,
      if (description != null) 'description': description,
      if (displayOrder != null) 'display_order': displayOrder,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  CategoriesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? imageUrl,
    Value<String?>? description,
    Value<int>? displayOrder,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      description: description ?? this.description,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (displayOrder.present) {
      map['display_order'] = Variable<int>(displayOrder.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('description: $description, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ProductsTable extends Products with TableInfo<$ProductsTable, Product> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _barcodeMeta = const VerificationMeta(
    'barcode',
  );
  @override
  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
    'barcode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
    'price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uomMeta = const VerificationMeta('uom');
  @override
  late final GeneratedColumn<String> uom = GeneratedColumn<String>(
    'uom',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unit'),
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stationIdMeta = const VerificationMeta(
    'stationId',
  );
  @override
  late final GeneratedColumn<int> stationId = GeneratedColumn<int>(
    'station_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tvaAmountMeta = const VerificationMeta(
    'tvaAmount',
  );
  @override
  late final GeneratedColumn<double> tvaAmount = GeneratedColumn<double>(
    'tva_amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _discountAmountMeta = const VerificationMeta(
    'discountAmount',
  );
  @override
  late final GeneratedColumn<double> discountAmount = GeneratedColumn<double>(
    'discount_amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _finalPriceMeta = const VerificationMeta(
    'finalPrice',
  );
  @override
  late final GeneratedColumn<double> finalPrice = GeneratedColumn<double>(
    'final_price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _isVariantMeta = const VerificationMeta(
    'isVariant',
  );
  @override
  late final GeneratedColumn<bool> isVariant = GeneratedColumn<bool>(
    'is_variant',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_variant" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    barcode,
    imageUrl,
    description,
    price,
    uom,
    categoryId,
    stationId,
    tvaAmount,
    discountAmount,
    finalPrice,
    isActive,
    isVariant,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'products';
  @override
  VerificationContext validateIntegrity(
    Insertable<Product> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('barcode')) {
      context.handle(
        _barcodeMeta,
        barcode.isAcceptableOrUnknown(data['barcode']!, _barcodeMeta),
      );
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('price')) {
      context.handle(
        _priceMeta,
        price.isAcceptableOrUnknown(data['price']!, _priceMeta),
      );
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('uom')) {
      context.handle(
        _uomMeta,
        uom.isAcceptableOrUnknown(data['uom']!, _uomMeta),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('station_id')) {
      context.handle(
        _stationIdMeta,
        stationId.isAcceptableOrUnknown(data['station_id']!, _stationIdMeta),
      );
    }
    if (data.containsKey('tva_amount')) {
      context.handle(
        _tvaAmountMeta,
        tvaAmount.isAcceptableOrUnknown(data['tva_amount']!, _tvaAmountMeta),
      );
    }
    if (data.containsKey('discount_amount')) {
      context.handle(
        _discountAmountMeta,
        discountAmount.isAcceptableOrUnknown(
          data['discount_amount']!,
          _discountAmountMeta,
        ),
      );
    }
    if (data.containsKey('final_price')) {
      context.handle(
        _finalPriceMeta,
        finalPrice.isAcceptableOrUnknown(data['final_price']!, _finalPriceMeta),
      );
    } else if (isInserting) {
      context.missing(_finalPriceMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('is_variant')) {
      context.handle(
        _isVariantMeta,
        isVariant.isAcceptableOrUnknown(data['is_variant']!, _isVariantMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Product map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Product(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      barcode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}barcode'],
      ),
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      price: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}price'],
      )!,
      uom: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uom'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}category_id'],
      ),
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}station_id'],
      ),
      tvaAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}tva_amount'],
      )!,
      discountAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}discount_amount'],
      )!,
      finalPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}final_price'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      isVariant: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_variant'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProductsTable createAlias(String alias) {
    return $ProductsTable(attachedDatabase, alias);
  }
}

class Product extends DataClass implements Insertable<Product> {
  final int id;
  final String name;
  final String? barcode;
  final String? imageUrl;
  final String? description;
  final double price;
  final String uom;
  final int? categoryId;
  final int? stationId;
  final double tvaAmount;
  final double discountAmount;
  final double finalPrice;
  final bool isActive;
  final bool isVariant;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Product({
    required this.id,
    required this.name,
    this.barcode,
    this.imageUrl,
    this.description,
    required this.price,
    required this.uom,
    this.categoryId,
    this.stationId,
    required this.tvaAmount,
    required this.discountAmount,
    required this.finalPrice,
    required this.isActive,
    required this.isVariant,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || barcode != null) {
      map['barcode'] = Variable<String>(barcode);
    }
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['price'] = Variable<double>(price);
    map['uom'] = Variable<String>(uom);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<int>(categoryId);
    }
    if (!nullToAbsent || stationId != null) {
      map['station_id'] = Variable<int>(stationId);
    }
    map['tva_amount'] = Variable<double>(tvaAmount);
    map['discount_amount'] = Variable<double>(discountAmount);
    map['final_price'] = Variable<double>(finalPrice);
    map['is_active'] = Variable<bool>(isActive);
    map['is_variant'] = Variable<bool>(isVariant);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProductsCompanion toCompanion(bool nullToAbsent) {
    return ProductsCompanion(
      id: Value(id),
      name: Value(name),
      barcode: barcode == null && nullToAbsent
          ? const Value.absent()
          : Value(barcode),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      price: Value(price),
      uom: Value(uom),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      stationId: stationId == null && nullToAbsent
          ? const Value.absent()
          : Value(stationId),
      tvaAmount: Value(tvaAmount),
      discountAmount: Value(discountAmount),
      finalPrice: Value(finalPrice),
      isActive: Value(isActive),
      isVariant: Value(isVariant),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Product.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Product(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      barcode: serializer.fromJson<String?>(json['barcode']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      description: serializer.fromJson<String?>(json['description']),
      price: serializer.fromJson<double>(json['price']),
      uom: serializer.fromJson<String>(json['uom']),
      categoryId: serializer.fromJson<int?>(json['categoryId']),
      stationId: serializer.fromJson<int?>(json['stationId']),
      tvaAmount: serializer.fromJson<double>(json['tvaAmount']),
      discountAmount: serializer.fromJson<double>(json['discountAmount']),
      finalPrice: serializer.fromJson<double>(json['finalPrice']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      isVariant: serializer.fromJson<bool>(json['isVariant']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'barcode': serializer.toJson<String?>(barcode),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'description': serializer.toJson<String?>(description),
      'price': serializer.toJson<double>(price),
      'uom': serializer.toJson<String>(uom),
      'categoryId': serializer.toJson<int?>(categoryId),
      'stationId': serializer.toJson<int?>(stationId),
      'tvaAmount': serializer.toJson<double>(tvaAmount),
      'discountAmount': serializer.toJson<double>(discountAmount),
      'finalPrice': serializer.toJson<double>(finalPrice),
      'isActive': serializer.toJson<bool>(isActive),
      'isVariant': serializer.toJson<bool>(isVariant),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Product copyWith({
    int? id,
    String? name,
    Value<String?> barcode = const Value.absent(),
    Value<String?> imageUrl = const Value.absent(),
    Value<String?> description = const Value.absent(),
    double? price,
    String? uom,
    Value<int?> categoryId = const Value.absent(),
    Value<int?> stationId = const Value.absent(),
    double? tvaAmount,
    double? discountAmount,
    double? finalPrice,
    bool? isActive,
    bool? isVariant,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Product(
    id: id ?? this.id,
    name: name ?? this.name,
    barcode: barcode.present ? barcode.value : this.barcode,
    imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
    description: description.present ? description.value : this.description,
    price: price ?? this.price,
    uom: uom ?? this.uom,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    stationId: stationId.present ? stationId.value : this.stationId,
    tvaAmount: tvaAmount ?? this.tvaAmount,
    discountAmount: discountAmount ?? this.discountAmount,
    finalPrice: finalPrice ?? this.finalPrice,
    isActive: isActive ?? this.isActive,
    isVariant: isVariant ?? this.isVariant,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Product copyWithCompanion(ProductsCompanion data) {
    return Product(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      barcode: data.barcode.present ? data.barcode.value : this.barcode,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      description: data.description.present
          ? data.description.value
          : this.description,
      price: data.price.present ? data.price.value : this.price,
      uom: data.uom.present ? data.uom.value : this.uom,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      tvaAmount: data.tvaAmount.present ? data.tvaAmount.value : this.tvaAmount,
      discountAmount: data.discountAmount.present
          ? data.discountAmount.value
          : this.discountAmount,
      finalPrice: data.finalPrice.present
          ? data.finalPrice.value
          : this.finalPrice,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      isVariant: data.isVariant.present ? data.isVariant.value : this.isVariant,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Product(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('barcode: $barcode, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('description: $description, ')
          ..write('price: $price, ')
          ..write('uom: $uom, ')
          ..write('categoryId: $categoryId, ')
          ..write('stationId: $stationId, ')
          ..write('tvaAmount: $tvaAmount, ')
          ..write('discountAmount: $discountAmount, ')
          ..write('finalPrice: $finalPrice, ')
          ..write('isActive: $isActive, ')
          ..write('isVariant: $isVariant, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    barcode,
    imageUrl,
    description,
    price,
    uom,
    categoryId,
    stationId,
    tvaAmount,
    discountAmount,
    finalPrice,
    isActive,
    isVariant,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Product &&
          other.id == this.id &&
          other.name == this.name &&
          other.barcode == this.barcode &&
          other.imageUrl == this.imageUrl &&
          other.description == this.description &&
          other.price == this.price &&
          other.uom == this.uom &&
          other.categoryId == this.categoryId &&
          other.stationId == this.stationId &&
          other.tvaAmount == this.tvaAmount &&
          other.discountAmount == this.discountAmount &&
          other.finalPrice == this.finalPrice &&
          other.isActive == this.isActive &&
          other.isVariant == this.isVariant &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProductsCompanion extends UpdateCompanion<Product> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> barcode;
  final Value<String?> imageUrl;
  final Value<String?> description;
  final Value<double> price;
  final Value<String> uom;
  final Value<int?> categoryId;
  final Value<int?> stationId;
  final Value<double> tvaAmount;
  final Value<double> discountAmount;
  final Value<double> finalPrice;
  final Value<bool> isActive;
  final Value<bool> isVariant;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const ProductsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.barcode = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.description = const Value.absent(),
    this.price = const Value.absent(),
    this.uom = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.stationId = const Value.absent(),
    this.tvaAmount = const Value.absent(),
    this.discountAmount = const Value.absent(),
    this.finalPrice = const Value.absent(),
    this.isActive = const Value.absent(),
    this.isVariant = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ProductsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.barcode = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.description = const Value.absent(),
    required double price,
    this.uom = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.stationId = const Value.absent(),
    this.tvaAmount = const Value.absent(),
    this.discountAmount = const Value.absent(),
    required double finalPrice,
    this.isActive = const Value.absent(),
    this.isVariant = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name),
       price = Value(price),
       finalPrice = Value(finalPrice);
  static Insertable<Product> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? barcode,
    Expression<String>? imageUrl,
    Expression<String>? description,
    Expression<double>? price,
    Expression<String>? uom,
    Expression<int>? categoryId,
    Expression<int>? stationId,
    Expression<double>? tvaAmount,
    Expression<double>? discountAmount,
    Expression<double>? finalPrice,
    Expression<bool>? isActive,
    Expression<bool>? isVariant,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (barcode != null) 'barcode': barcode,
      if (imageUrl != null) 'image_url': imageUrl,
      if (description != null) 'description': description,
      if (price != null) 'price': price,
      if (uom != null) 'uom': uom,
      if (categoryId != null) 'category_id': categoryId,
      if (stationId != null) 'station_id': stationId,
      if (tvaAmount != null) 'tva_amount': tvaAmount,
      if (discountAmount != null) 'discount_amount': discountAmount,
      if (finalPrice != null) 'final_price': finalPrice,
      if (isActive != null) 'is_active': isActive,
      if (isVariant != null) 'is_variant': isVariant,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ProductsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? barcode,
    Value<String?>? imageUrl,
    Value<String?>? description,
    Value<double>? price,
    Value<String>? uom,
    Value<int?>? categoryId,
    Value<int?>? stationId,
    Value<double>? tvaAmount,
    Value<double>? discountAmount,
    Value<double>? finalPrice,
    Value<bool>? isActive,
    Value<bool>? isVariant,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return ProductsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      imageUrl: imageUrl ?? this.imageUrl,
      description: description ?? this.description,
      price: price ?? this.price,
      uom: uom ?? this.uom,
      categoryId: categoryId ?? this.categoryId,
      stationId: stationId ?? this.stationId,
      tvaAmount: tvaAmount ?? this.tvaAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      finalPrice: finalPrice ?? this.finalPrice,
      isActive: isActive ?? this.isActive,
      isVariant: isVariant ?? this.isVariant,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (barcode.present) {
      map['barcode'] = Variable<String>(barcode.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (uom.present) {
      map['uom'] = Variable<String>(uom.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (stationId.present) {
      map['station_id'] = Variable<int>(stationId.value);
    }
    if (tvaAmount.present) {
      map['tva_amount'] = Variable<double>(tvaAmount.value);
    }
    if (discountAmount.present) {
      map['discount_amount'] = Variable<double>(discountAmount.value);
    }
    if (finalPrice.present) {
      map['final_price'] = Variable<double>(finalPrice.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (isVariant.present) {
      map['is_variant'] = Variable<bool>(isVariant.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('barcode: $barcode, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('description: $description, ')
          ..write('price: $price, ')
          ..write('uom: $uom, ')
          ..write('categoryId: $categoryId, ')
          ..write('stationId: $stationId, ')
          ..write('tvaAmount: $tvaAmount, ')
          ..write('discountAmount: $discountAmount, ')
          ..write('finalPrice: $finalPrice, ')
          ..write('isActive: $isActive, ')
          ..write('isVariant: $isVariant, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ProductVariantsTable extends ProductVariants
    with TableInfo<$ProductVariantsTable, ProductVariant> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductVariantsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<int> productId = GeneratedColumn<int>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _barcodeMeta = const VerificationMeta(
    'barcode',
  );
  @override
  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
    'barcode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _skuMeta = const VerificationMeta('sku');
  @override
  late final GeneratedColumn<String> sku = GeneratedColumn<String>(
    'sku',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
    'tags',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
    'price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _costMeta = const VerificationMeta('cost');
  @override
  late final GeneratedColumn<double> cost = GeneratedColumn<double>(
    'cost',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tvaAmountMeta = const VerificationMeta(
    'tvaAmount',
  );
  @override
  late final GeneratedColumn<double> tvaAmount = GeneratedColumn<double>(
    'tva_amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    productId,
    name,
    barcode,
    sku,
    description,
    imageUrl,
    color,
    tags,
    price,
    cost,
    tvaAmount,
    isActive,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_variants';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProductVariant> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('barcode')) {
      context.handle(
        _barcodeMeta,
        barcode.isAcceptableOrUnknown(data['barcode']!, _barcodeMeta),
      );
    }
    if (data.containsKey('sku')) {
      context.handle(
        _skuMeta,
        sku.isAcceptableOrUnknown(data['sku']!, _skuMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('tags')) {
      context.handle(
        _tagsMeta,
        tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta),
      );
    }
    if (data.containsKey('price')) {
      context.handle(
        _priceMeta,
        price.isAcceptableOrUnknown(data['price']!, _priceMeta),
      );
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('cost')) {
      context.handle(
        _costMeta,
        cost.isAcceptableOrUnknown(data['cost']!, _costMeta),
      );
    }
    if (data.containsKey('tva_amount')) {
      context.handle(
        _tvaAmountMeta,
        tvaAmount.isAcceptableOrUnknown(data['tva_amount']!, _tvaAmountMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductVariant map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductVariant(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}product_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      barcode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}barcode'],
      ),
      sku: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sku'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      ),
      tags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags'],
      ),
      price: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}price'],
      )!,
      cost: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cost'],
      ),
      tvaAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}tva_amount'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProductVariantsTable createAlias(String alias) {
    return $ProductVariantsTable(attachedDatabase, alias);
  }
}

class ProductVariant extends DataClass implements Insertable<ProductVariant> {
  final int id;
  final int productId;
  final String name;
  final String? barcode;
  final String? sku;
  final String? description;
  final String? imageUrl;
  final String? color;
  final String? tags;
  final double price;
  final double? cost;
  final double tvaAmount;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ProductVariant({
    required this.id,
    required this.productId,
    required this.name,
    this.barcode,
    this.sku,
    this.description,
    this.imageUrl,
    this.color,
    this.tags,
    required this.price,
    this.cost,
    required this.tvaAmount,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['product_id'] = Variable<int>(productId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || barcode != null) {
      map['barcode'] = Variable<String>(barcode);
    }
    if (!nullToAbsent || sku != null) {
      map['sku'] = Variable<String>(sku);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    if (!nullToAbsent || tags != null) {
      map['tags'] = Variable<String>(tags);
    }
    map['price'] = Variable<double>(price);
    if (!nullToAbsent || cost != null) {
      map['cost'] = Variable<double>(cost);
    }
    map['tva_amount'] = Variable<double>(tvaAmount);
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProductVariantsCompanion toCompanion(bool nullToAbsent) {
    return ProductVariantsCompanion(
      id: Value(id),
      productId: Value(productId),
      name: Value(name),
      barcode: barcode == null && nullToAbsent
          ? const Value.absent()
          : Value(barcode),
      sku: sku == null && nullToAbsent ? const Value.absent() : Value(sku),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
      tags: tags == null && nullToAbsent ? const Value.absent() : Value(tags),
      price: Value(price),
      cost: cost == null && nullToAbsent ? const Value.absent() : Value(cost),
      tvaAmount: Value(tvaAmount),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProductVariant.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductVariant(
      id: serializer.fromJson<int>(json['id']),
      productId: serializer.fromJson<int>(json['productId']),
      name: serializer.fromJson<String>(json['name']),
      barcode: serializer.fromJson<String?>(json['barcode']),
      sku: serializer.fromJson<String?>(json['sku']),
      description: serializer.fromJson<String?>(json['description']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      color: serializer.fromJson<String?>(json['color']),
      tags: serializer.fromJson<String?>(json['tags']),
      price: serializer.fromJson<double>(json['price']),
      cost: serializer.fromJson<double?>(json['cost']),
      tvaAmount: serializer.fromJson<double>(json['tvaAmount']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'productId': serializer.toJson<int>(productId),
      'name': serializer.toJson<String>(name),
      'barcode': serializer.toJson<String?>(barcode),
      'sku': serializer.toJson<String?>(sku),
      'description': serializer.toJson<String?>(description),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'color': serializer.toJson<String?>(color),
      'tags': serializer.toJson<String?>(tags),
      'price': serializer.toJson<double>(price),
      'cost': serializer.toJson<double?>(cost),
      'tvaAmount': serializer.toJson<double>(tvaAmount),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ProductVariant copyWith({
    int? id,
    int? productId,
    String? name,
    Value<String?> barcode = const Value.absent(),
    Value<String?> sku = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<String?> imageUrl = const Value.absent(),
    Value<String?> color = const Value.absent(),
    Value<String?> tags = const Value.absent(),
    double? price,
    Value<double?> cost = const Value.absent(),
    double? tvaAmount,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ProductVariant(
    id: id ?? this.id,
    productId: productId ?? this.productId,
    name: name ?? this.name,
    barcode: barcode.present ? barcode.value : this.barcode,
    sku: sku.present ? sku.value : this.sku,
    description: description.present ? description.value : this.description,
    imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
    color: color.present ? color.value : this.color,
    tags: tags.present ? tags.value : this.tags,
    price: price ?? this.price,
    cost: cost.present ? cost.value : this.cost,
    tvaAmount: tvaAmount ?? this.tvaAmount,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ProductVariant copyWithCompanion(ProductVariantsCompanion data) {
    return ProductVariant(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      name: data.name.present ? data.name.value : this.name,
      barcode: data.barcode.present ? data.barcode.value : this.barcode,
      sku: data.sku.present ? data.sku.value : this.sku,
      description: data.description.present
          ? data.description.value
          : this.description,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      color: data.color.present ? data.color.value : this.color,
      tags: data.tags.present ? data.tags.value : this.tags,
      price: data.price.present ? data.price.value : this.price,
      cost: data.cost.present ? data.cost.value : this.cost,
      tvaAmount: data.tvaAmount.present ? data.tvaAmount.value : this.tvaAmount,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductVariant(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('name: $name, ')
          ..write('barcode: $barcode, ')
          ..write('sku: $sku, ')
          ..write('description: $description, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('color: $color, ')
          ..write('tags: $tags, ')
          ..write('price: $price, ')
          ..write('cost: $cost, ')
          ..write('tvaAmount: $tvaAmount, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    productId,
    name,
    barcode,
    sku,
    description,
    imageUrl,
    color,
    tags,
    price,
    cost,
    tvaAmount,
    isActive,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductVariant &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.name == this.name &&
          other.barcode == this.barcode &&
          other.sku == this.sku &&
          other.description == this.description &&
          other.imageUrl == this.imageUrl &&
          other.color == this.color &&
          other.tags == this.tags &&
          other.price == this.price &&
          other.cost == this.cost &&
          other.tvaAmount == this.tvaAmount &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProductVariantsCompanion extends UpdateCompanion<ProductVariant> {
  final Value<int> id;
  final Value<int> productId;
  final Value<String> name;
  final Value<String?> barcode;
  final Value<String?> sku;
  final Value<String?> description;
  final Value<String?> imageUrl;
  final Value<String?> color;
  final Value<String?> tags;
  final Value<double> price;
  final Value<double?> cost;
  final Value<double> tvaAmount;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const ProductVariantsCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.name = const Value.absent(),
    this.barcode = const Value.absent(),
    this.sku = const Value.absent(),
    this.description = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.color = const Value.absent(),
    this.tags = const Value.absent(),
    this.price = const Value.absent(),
    this.cost = const Value.absent(),
    this.tvaAmount = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ProductVariantsCompanion.insert({
    this.id = const Value.absent(),
    required int productId,
    required String name,
    this.barcode = const Value.absent(),
    this.sku = const Value.absent(),
    this.description = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.color = const Value.absent(),
    this.tags = const Value.absent(),
    required double price,
    this.cost = const Value.absent(),
    this.tvaAmount = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : productId = Value(productId),
       name = Value(name),
       price = Value(price);
  static Insertable<ProductVariant> custom({
    Expression<int>? id,
    Expression<int>? productId,
    Expression<String>? name,
    Expression<String>? barcode,
    Expression<String>? sku,
    Expression<String>? description,
    Expression<String>? imageUrl,
    Expression<String>? color,
    Expression<String>? tags,
    Expression<double>? price,
    Expression<double>? cost,
    Expression<double>? tvaAmount,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (name != null) 'name': name,
      if (barcode != null) 'barcode': barcode,
      if (sku != null) 'sku': sku,
      if (description != null) 'description': description,
      if (imageUrl != null) 'image_url': imageUrl,
      if (color != null) 'color': color,
      if (tags != null) 'tags': tags,
      if (price != null) 'price': price,
      if (cost != null) 'cost': cost,
      if (tvaAmount != null) 'tva_amount': tvaAmount,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ProductVariantsCompanion copyWith({
    Value<int>? id,
    Value<int>? productId,
    Value<String>? name,
    Value<String?>? barcode,
    Value<String?>? sku,
    Value<String?>? description,
    Value<String?>? imageUrl,
    Value<String?>? color,
    Value<String?>? tags,
    Value<double>? price,
    Value<double?>? cost,
    Value<double>? tvaAmount,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return ProductVariantsCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      name: name ?? this.name,
      barcode: barcode ?? this.barcode,
      sku: sku ?? this.sku,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      color: color ?? this.color,
      tags: tags ?? this.tags,
      price: price ?? this.price,
      cost: cost ?? this.cost,
      tvaAmount: tvaAmount ?? this.tvaAmount,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<int>(productId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (barcode.present) {
      map['barcode'] = Variable<String>(barcode.value);
    }
    if (sku.present) {
      map['sku'] = Variable<String>(sku.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (cost.present) {
      map['cost'] = Variable<double>(cost.value);
    }
    if (tvaAmount.present) {
      map['tva_amount'] = Variable<double>(tvaAmount.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductVariantsCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('name: $name, ')
          ..write('barcode: $barcode, ')
          ..write('sku: $sku, ')
          ..write('description: $description, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('color: $color, ')
          ..write('tags: $tags, ')
          ..write('price: $price, ')
          ..write('cost: $cost, ')
          ..write('tvaAmount: $tvaAmount, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $VariantAttributeValuesTable extends VariantAttributeValues
    with TableInfo<$VariantAttributeValuesTable, VariantAttributeValue> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VariantAttributeValuesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _variantIdMeta = const VerificationMeta(
    'variantId',
  );
  @override
  late final GeneratedColumn<int> variantId = GeneratedColumn<int>(
    'variant_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attributeIdMeta = const VerificationMeta(
    'attributeId',
  );
  @override
  late final GeneratedColumn<int> attributeId = GeneratedColumn<int>(
    'attribute_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attributeNameMeta = const VerificationMeta(
    'attributeName',
  );
  @override
  late final GeneratedColumn<String> attributeName = GeneratedColumn<String>(
    'attribute_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _valueIdMeta = const VerificationMeta(
    'valueId',
  );
  @override
  late final GeneratedColumn<int> valueId = GeneratedColumn<int>(
    'value_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    variantId,
    attributeId,
    attributeName,
    valueId,
    value,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'variant_attribute_values';
  @override
  VerificationContext validateIntegrity(
    Insertable<VariantAttributeValue> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('variant_id')) {
      context.handle(
        _variantIdMeta,
        variantId.isAcceptableOrUnknown(data['variant_id']!, _variantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_variantIdMeta);
    }
    if (data.containsKey('attribute_id')) {
      context.handle(
        _attributeIdMeta,
        attributeId.isAcceptableOrUnknown(
          data['attribute_id']!,
          _attributeIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attributeIdMeta);
    }
    if (data.containsKey('attribute_name')) {
      context.handle(
        _attributeNameMeta,
        attributeName.isAcceptableOrUnknown(
          data['attribute_name']!,
          _attributeNameMeta,
        ),
      );
    }
    if (data.containsKey('value_id')) {
      context.handle(
        _valueIdMeta,
        valueId.isAcceptableOrUnknown(data['value_id']!, _valueIdMeta),
      );
    } else if (isInserting) {
      context.missing(_valueIdMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VariantAttributeValue map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VariantAttributeValue(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      variantId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}variant_id'],
      )!,
      attributeId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attribute_id'],
      )!,
      attributeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attribute_name'],
      ),
      valueId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}value_id'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $VariantAttributeValuesTable createAlias(String alias) {
    return $VariantAttributeValuesTable(attachedDatabase, alias);
  }
}

class VariantAttributeValue extends DataClass
    implements Insertable<VariantAttributeValue> {
  final int id;
  final int variantId;
  final int attributeId;
  final String? attributeName;
  final int valueId;
  final String? value;
  final DateTime createdAt;
  const VariantAttributeValue({
    required this.id,
    required this.variantId,
    required this.attributeId,
    this.attributeName,
    required this.valueId,
    this.value,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['variant_id'] = Variable<int>(variantId);
    map['attribute_id'] = Variable<int>(attributeId);
    if (!nullToAbsent || attributeName != null) {
      map['attribute_name'] = Variable<String>(attributeName);
    }
    map['value_id'] = Variable<int>(valueId);
    if (!nullToAbsent || value != null) {
      map['value'] = Variable<String>(value);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  VariantAttributeValuesCompanion toCompanion(bool nullToAbsent) {
    return VariantAttributeValuesCompanion(
      id: Value(id),
      variantId: Value(variantId),
      attributeId: Value(attributeId),
      attributeName: attributeName == null && nullToAbsent
          ? const Value.absent()
          : Value(attributeName),
      valueId: Value(valueId),
      value: value == null && nullToAbsent
          ? const Value.absent()
          : Value(value),
      createdAt: Value(createdAt),
    );
  }

  factory VariantAttributeValue.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VariantAttributeValue(
      id: serializer.fromJson<int>(json['id']),
      variantId: serializer.fromJson<int>(json['variantId']),
      attributeId: serializer.fromJson<int>(json['attributeId']),
      attributeName: serializer.fromJson<String?>(json['attributeName']),
      valueId: serializer.fromJson<int>(json['valueId']),
      value: serializer.fromJson<String?>(json['value']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'variantId': serializer.toJson<int>(variantId),
      'attributeId': serializer.toJson<int>(attributeId),
      'attributeName': serializer.toJson<String?>(attributeName),
      'valueId': serializer.toJson<int>(valueId),
      'value': serializer.toJson<String?>(value),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  VariantAttributeValue copyWith({
    int? id,
    int? variantId,
    int? attributeId,
    Value<String?> attributeName = const Value.absent(),
    int? valueId,
    Value<String?> value = const Value.absent(),
    DateTime? createdAt,
  }) => VariantAttributeValue(
    id: id ?? this.id,
    variantId: variantId ?? this.variantId,
    attributeId: attributeId ?? this.attributeId,
    attributeName: attributeName.present
        ? attributeName.value
        : this.attributeName,
    valueId: valueId ?? this.valueId,
    value: value.present ? value.value : this.value,
    createdAt: createdAt ?? this.createdAt,
  );
  VariantAttributeValue copyWithCompanion(
    VariantAttributeValuesCompanion data,
  ) {
    return VariantAttributeValue(
      id: data.id.present ? data.id.value : this.id,
      variantId: data.variantId.present ? data.variantId.value : this.variantId,
      attributeId: data.attributeId.present
          ? data.attributeId.value
          : this.attributeId,
      attributeName: data.attributeName.present
          ? data.attributeName.value
          : this.attributeName,
      valueId: data.valueId.present ? data.valueId.value : this.valueId,
      value: data.value.present ? data.value.value : this.value,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VariantAttributeValue(')
          ..write('id: $id, ')
          ..write('variantId: $variantId, ')
          ..write('attributeId: $attributeId, ')
          ..write('attributeName: $attributeName, ')
          ..write('valueId: $valueId, ')
          ..write('value: $value, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    variantId,
    attributeId,
    attributeName,
    valueId,
    value,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VariantAttributeValue &&
          other.id == this.id &&
          other.variantId == this.variantId &&
          other.attributeId == this.attributeId &&
          other.attributeName == this.attributeName &&
          other.valueId == this.valueId &&
          other.value == this.value &&
          other.createdAt == this.createdAt);
}

class VariantAttributeValuesCompanion
    extends UpdateCompanion<VariantAttributeValue> {
  final Value<int> id;
  final Value<int> variantId;
  final Value<int> attributeId;
  final Value<String?> attributeName;
  final Value<int> valueId;
  final Value<String?> value;
  final Value<DateTime> createdAt;
  const VariantAttributeValuesCompanion({
    this.id = const Value.absent(),
    this.variantId = const Value.absent(),
    this.attributeId = const Value.absent(),
    this.attributeName = const Value.absent(),
    this.valueId = const Value.absent(),
    this.value = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  VariantAttributeValuesCompanion.insert({
    this.id = const Value.absent(),
    required int variantId,
    required int attributeId,
    this.attributeName = const Value.absent(),
    required int valueId,
    this.value = const Value.absent(),
    this.createdAt = const Value.absent(),
  }) : variantId = Value(variantId),
       attributeId = Value(attributeId),
       valueId = Value(valueId);
  static Insertable<VariantAttributeValue> custom({
    Expression<int>? id,
    Expression<int>? variantId,
    Expression<int>? attributeId,
    Expression<String>? attributeName,
    Expression<int>? valueId,
    Expression<String>? value,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (variantId != null) 'variant_id': variantId,
      if (attributeId != null) 'attribute_id': attributeId,
      if (attributeName != null) 'attribute_name': attributeName,
      if (valueId != null) 'value_id': valueId,
      if (value != null) 'value': value,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  VariantAttributeValuesCompanion copyWith({
    Value<int>? id,
    Value<int>? variantId,
    Value<int>? attributeId,
    Value<String?>? attributeName,
    Value<int>? valueId,
    Value<String?>? value,
    Value<DateTime>? createdAt,
  }) {
    return VariantAttributeValuesCompanion(
      id: id ?? this.id,
      variantId: variantId ?? this.variantId,
      attributeId: attributeId ?? this.attributeId,
      attributeName: attributeName ?? this.attributeName,
      valueId: valueId ?? this.valueId,
      value: value ?? this.value,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (variantId.present) {
      map['variant_id'] = Variable<int>(variantId.value);
    }
    if (attributeId.present) {
      map['attribute_id'] = Variable<int>(attributeId.value);
    }
    if (attributeName.present) {
      map['attribute_name'] = Variable<String>(attributeName.value);
    }
    if (valueId.present) {
      map['value_id'] = Variable<int>(valueId.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VariantAttributeValuesCompanion(')
          ..write('id: $id, ')
          ..write('variantId: $variantId, ')
          ..write('attributeId: $attributeId, ')
          ..write('attributeName: $attributeName, ')
          ..write('valueId: $valueId, ')
          ..write('value: $value, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $UsersTable extends Users with TableInfo<$UsersTable, User> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _passwordMeta = const VerificationMeta(
    'password',
  );
  @override
  late final GeneratedColumn<String> password = GeneratedColumn<String>(
    'password',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstNameMeta = const VerificationMeta(
    'firstName',
  );
  @override
  late final GeneratedColumn<String> firstName = GeneratedColumn<String>(
    'first_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastNameMeta = const VerificationMeta(
    'lastName',
  );
  @override
  late final GeneratedColumn<String> lastName = GeneratedColumn<String>(
    'last_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accessTokenMeta = const VerificationMeta(
    'accessToken',
  );
  @override
  late final GeneratedColumn<String> accessToken = GeneratedColumn<String>(
    'access_token',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _refreshTokenMeta = const VerificationMeta(
    'refreshToken',
  );
  @override
  late final GeneratedColumn<String> refreshToken = GeneratedColumn<String>(
    'refresh_token',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _permissionsMeta = const VerificationMeta(
    'permissions',
  );
  @override
  late final GeneratedColumn<String> permissions = GeneratedColumn<String>(
    'permissions',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _lastLoginMeta = const VerificationMeta(
    'lastLogin',
  );
  @override
  late final GeneratedColumn<DateTime> lastLogin = GeneratedColumn<DateTime>(
    'last_login',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    username,
    password,
    firstName,
    lastName,
    type,
    imageUrl,
    accessToken,
    refreshToken,
    permissions,
    createdAt,
    updatedAt,
    lastLogin,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users';
  @override
  VerificationContext validateIntegrity(
    Insertable<User> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('password')) {
      context.handle(
        _passwordMeta,
        password.isAcceptableOrUnknown(data['password']!, _passwordMeta),
      );
    } else if (isInserting) {
      context.missing(_passwordMeta);
    }
    if (data.containsKey('first_name')) {
      context.handle(
        _firstNameMeta,
        firstName.isAcceptableOrUnknown(data['first_name']!, _firstNameMeta),
      );
    } else if (isInserting) {
      context.missing(_firstNameMeta);
    }
    if (data.containsKey('last_name')) {
      context.handle(
        _lastNameMeta,
        lastName.isAcceptableOrUnknown(data['last_name']!, _lastNameMeta),
      );
    } else if (isInserting) {
      context.missing(_lastNameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    }
    if (data.containsKey('access_token')) {
      context.handle(
        _accessTokenMeta,
        accessToken.isAcceptableOrUnknown(
          data['access_token']!,
          _accessTokenMeta,
        ),
      );
    }
    if (data.containsKey('refresh_token')) {
      context.handle(
        _refreshTokenMeta,
        refreshToken.isAcceptableOrUnknown(
          data['refresh_token']!,
          _refreshTokenMeta,
        ),
      );
    }
    if (data.containsKey('permissions')) {
      context.handle(
        _permissionsMeta,
        permissions.isAcceptableOrUnknown(
          data['permissions']!,
          _permissionsMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('last_login')) {
      context.handle(
        _lastLoginMeta,
        lastLogin.isAcceptableOrUnknown(data['last_login']!, _lastLoginMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  User map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return User(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      password: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password'],
      )!,
      firstName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_name'],
      )!,
      lastName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      ),
      accessToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}access_token'],
      ),
      refreshToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}refresh_token'],
      ),
      permissions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}permissions'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      lastLogin: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_login'],
      ),
    );
  }

  @override
  $UsersTable createAlias(String alias) {
    return $UsersTable(attachedDatabase, alias);
  }
}

class User extends DataClass implements Insertable<User> {
  final int id;
  final String username;
  final String password;
  final String firstName;
  final String lastName;
  final String type;
  final String? imageUrl;
  final String? accessToken;
  final String? refreshToken;
  final String? permissions;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLogin;
  const User({
    required this.id,
    required this.username,
    required this.password,
    required this.firstName,
    required this.lastName,
    required this.type,
    this.imageUrl,
    this.accessToken,
    this.refreshToken,
    this.permissions,
    required this.createdAt,
    required this.updatedAt,
    this.lastLogin,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['username'] = Variable<String>(username);
    map['password'] = Variable<String>(password);
    map['first_name'] = Variable<String>(firstName);
    map['last_name'] = Variable<String>(lastName);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    if (!nullToAbsent || accessToken != null) {
      map['access_token'] = Variable<String>(accessToken);
    }
    if (!nullToAbsent || refreshToken != null) {
      map['refresh_token'] = Variable<String>(refreshToken);
    }
    if (!nullToAbsent || permissions != null) {
      map['permissions'] = Variable<String>(permissions);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || lastLogin != null) {
      map['last_login'] = Variable<DateTime>(lastLogin);
    }
    return map;
  }

  UsersCompanion toCompanion(bool nullToAbsent) {
    return UsersCompanion(
      id: Value(id),
      username: Value(username),
      password: Value(password),
      firstName: Value(firstName),
      lastName: Value(lastName),
      type: Value(type),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      accessToken: accessToken == null && nullToAbsent
          ? const Value.absent()
          : Value(accessToken),
      refreshToken: refreshToken == null && nullToAbsent
          ? const Value.absent()
          : Value(refreshToken),
      permissions: permissions == null && nullToAbsent
          ? const Value.absent()
          : Value(permissions),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      lastLogin: lastLogin == null && nullToAbsent
          ? const Value.absent()
          : Value(lastLogin),
    );
  }

  factory User.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return User(
      id: serializer.fromJson<int>(json['id']),
      username: serializer.fromJson<String>(json['username']),
      password: serializer.fromJson<String>(json['password']),
      firstName: serializer.fromJson<String>(json['firstName']),
      lastName: serializer.fromJson<String>(json['lastName']),
      type: serializer.fromJson<String>(json['type']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      accessToken: serializer.fromJson<String?>(json['accessToken']),
      refreshToken: serializer.fromJson<String?>(json['refreshToken']),
      permissions: serializer.fromJson<String?>(json['permissions']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      lastLogin: serializer.fromJson<DateTime?>(json['lastLogin']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'username': serializer.toJson<String>(username),
      'password': serializer.toJson<String>(password),
      'firstName': serializer.toJson<String>(firstName),
      'lastName': serializer.toJson<String>(lastName),
      'type': serializer.toJson<String>(type),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'accessToken': serializer.toJson<String?>(accessToken),
      'refreshToken': serializer.toJson<String?>(refreshToken),
      'permissions': serializer.toJson<String?>(permissions),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'lastLogin': serializer.toJson<DateTime?>(lastLogin),
    };
  }

  User copyWith({
    int? id,
    String? username,
    String? password,
    String? firstName,
    String? lastName,
    String? type,
    Value<String?> imageUrl = const Value.absent(),
    Value<String?> accessToken = const Value.absent(),
    Value<String?> refreshToken = const Value.absent(),
    Value<String?> permissions = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> lastLogin = const Value.absent(),
  }) => User(
    id: id ?? this.id,
    username: username ?? this.username,
    password: password ?? this.password,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    type: type ?? this.type,
    imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
    accessToken: accessToken.present ? accessToken.value : this.accessToken,
    refreshToken: refreshToken.present ? refreshToken.value : this.refreshToken,
    permissions: permissions.present ? permissions.value : this.permissions,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lastLogin: lastLogin.present ? lastLogin.value : this.lastLogin,
  );
  User copyWithCompanion(UsersCompanion data) {
    return User(
      id: data.id.present ? data.id.value : this.id,
      username: data.username.present ? data.username.value : this.username,
      password: data.password.present ? data.password.value : this.password,
      firstName: data.firstName.present ? data.firstName.value : this.firstName,
      lastName: data.lastName.present ? data.lastName.value : this.lastName,
      type: data.type.present ? data.type.value : this.type,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      accessToken: data.accessToken.present
          ? data.accessToken.value
          : this.accessToken,
      refreshToken: data.refreshToken.present
          ? data.refreshToken.value
          : this.refreshToken,
      permissions: data.permissions.present
          ? data.permissions.value
          : this.permissions,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastLogin: data.lastLogin.present ? data.lastLogin.value : this.lastLogin,
    );
  }

  @override
  String toString() {
    return (StringBuffer('User(')
          ..write('id: $id, ')
          ..write('username: $username, ')
          ..write('password: $password, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('type: $type, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('accessToken: $accessToken, ')
          ..write('refreshToken: $refreshToken, ')
          ..write('permissions: $permissions, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastLogin: $lastLogin')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    username,
    password,
    firstName,
    lastName,
    type,
    imageUrl,
    accessToken,
    refreshToken,
    permissions,
    createdAt,
    updatedAt,
    lastLogin,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is User &&
          other.id == this.id &&
          other.username == this.username &&
          other.password == this.password &&
          other.firstName == this.firstName &&
          other.lastName == this.lastName &&
          other.type == this.type &&
          other.imageUrl == this.imageUrl &&
          other.accessToken == this.accessToken &&
          other.refreshToken == this.refreshToken &&
          other.permissions == this.permissions &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.lastLogin == this.lastLogin);
}

class UsersCompanion extends UpdateCompanion<User> {
  final Value<int> id;
  final Value<String> username;
  final Value<String> password;
  final Value<String> firstName;
  final Value<String> lastName;
  final Value<String> type;
  final Value<String?> imageUrl;
  final Value<String?> accessToken;
  final Value<String?> refreshToken;
  final Value<String?> permissions;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> lastLogin;
  const UsersCompanion({
    this.id = const Value.absent(),
    this.username = const Value.absent(),
    this.password = const Value.absent(),
    this.firstName = const Value.absent(),
    this.lastName = const Value.absent(),
    this.type = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.accessToken = const Value.absent(),
    this.refreshToken = const Value.absent(),
    this.permissions = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastLogin = const Value.absent(),
  });
  UsersCompanion.insert({
    this.id = const Value.absent(),
    required String username,
    required String password,
    required String firstName,
    required String lastName,
    required String type,
    this.imageUrl = const Value.absent(),
    this.accessToken = const Value.absent(),
    this.refreshToken = const Value.absent(),
    this.permissions = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastLogin = const Value.absent(),
  }) : username = Value(username),
       password = Value(password),
       firstName = Value(firstName),
       lastName = Value(lastName),
       type = Value(type);
  static Insertable<User> custom({
    Expression<int>? id,
    Expression<String>? username,
    Expression<String>? password,
    Expression<String>? firstName,
    Expression<String>? lastName,
    Expression<String>? type,
    Expression<String>? imageUrl,
    Expression<String>? accessToken,
    Expression<String>? refreshToken,
    Expression<String>? permissions,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? lastLogin,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (username != null) 'username': username,
      if (password != null) 'password': password,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (type != null) 'type': type,
      if (imageUrl != null) 'image_url': imageUrl,
      if (accessToken != null) 'access_token': accessToken,
      if (refreshToken != null) 'refresh_token': refreshToken,
      if (permissions != null) 'permissions': permissions,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastLogin != null) 'last_login': lastLogin,
    });
  }

  UsersCompanion copyWith({
    Value<int>? id,
    Value<String>? username,
    Value<String>? password,
    Value<String>? firstName,
    Value<String>? lastName,
    Value<String>? type,
    Value<String?>? imageUrl,
    Value<String?>? accessToken,
    Value<String?>? refreshToken,
    Value<String?>? permissions,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? lastLogin,
  }) {
    return UsersCompanion(
      id: id ?? this.id,
      username: username ?? this.username,
      password: password ?? this.password,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      type: type ?? this.type,
      imageUrl: imageUrl ?? this.imageUrl,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      permissions: permissions ?? this.permissions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLogin: lastLogin ?? this.lastLogin,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (password.present) {
      map['password'] = Variable<String>(password.value);
    }
    if (firstName.present) {
      map['first_name'] = Variable<String>(firstName.value);
    }
    if (lastName.present) {
      map['last_name'] = Variable<String>(lastName.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (accessToken.present) {
      map['access_token'] = Variable<String>(accessToken.value);
    }
    if (refreshToken.present) {
      map['refresh_token'] = Variable<String>(refreshToken.value);
    }
    if (permissions.present) {
      map['permissions'] = Variable<String>(permissions.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (lastLogin.present) {
      map['last_login'] = Variable<DateTime>(lastLogin.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersCompanion(')
          ..write('id: $id, ')
          ..write('username: $username, ')
          ..write('password: $password, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('type: $type, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('accessToken: $accessToken, ')
          ..write('refreshToken: $refreshToken, ')
          ..write('permissions: $permissions, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastLogin: $lastLogin')
          ..write(')'))
        .toString();
  }
}

class $ComponentsTable extends Components
    with TableInfo<$ComponentsTable, Component> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ComponentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
    'price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _componentGroupIdMeta = const VerificationMeta(
    'componentGroupId',
  );
  @override
  late final GeneratedColumn<int> componentGroupId = GeneratedColumn<int>(
    'component_group_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    imageUrl,
    price,
    componentGroupId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'components';
  @override
  VerificationContext validateIntegrity(
    Insertable<Component> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    }
    if (data.containsKey('price')) {
      context.handle(
        _priceMeta,
        price.isAcceptableOrUnknown(data['price']!, _priceMeta),
      );
    }
    if (data.containsKey('component_group_id')) {
      context.handle(
        _componentGroupIdMeta,
        componentGroupId.isAcceptableOrUnknown(
          data['component_group_id']!,
          _componentGroupIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Component map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Component(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      ),
      price: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}price'],
      )!,
      componentGroupId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}component_group_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ComponentsTable createAlias(String alias) {
    return $ComponentsTable(attachedDatabase, alias);
  }
}

class Component extends DataClass implements Insertable<Component> {
  final int id;
  final String name;
  final String? description;
  final String? imageUrl;
  final double price;
  final int? componentGroupId;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Component({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
    required this.price,
    this.componentGroupId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    map['price'] = Variable<double>(price);
    if (!nullToAbsent || componentGroupId != null) {
      map['component_group_id'] = Variable<int>(componentGroupId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ComponentsCompanion toCompanion(bool nullToAbsent) {
    return ComponentsCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      price: Value(price),
      componentGroupId: componentGroupId == null && nullToAbsent
          ? const Value.absent()
          : Value(componentGroupId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Component.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Component(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      price: serializer.fromJson<double>(json['price']),
      componentGroupId: serializer.fromJson<int?>(json['componentGroupId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'price': serializer.toJson<double>(price),
      'componentGroupId': serializer.toJson<int?>(componentGroupId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Component copyWith({
    int? id,
    String? name,
    Value<String?> description = const Value.absent(),
    Value<String?> imageUrl = const Value.absent(),
    double? price,
    Value<int?> componentGroupId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Component(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
    price: price ?? this.price,
    componentGroupId: componentGroupId.present
        ? componentGroupId.value
        : this.componentGroupId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Component copyWithCompanion(ComponentsCompanion data) {
    return Component(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      price: data.price.present ? data.price.value : this.price,
      componentGroupId: data.componentGroupId.present
          ? data.componentGroupId.value
          : this.componentGroupId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Component(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('price: $price, ')
          ..write('componentGroupId: $componentGroupId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    imageUrl,
    price,
    componentGroupId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Component &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.imageUrl == this.imageUrl &&
          other.price == this.price &&
          other.componentGroupId == this.componentGroupId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ComponentsCompanion extends UpdateCompanion<Component> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<String?> imageUrl;
  final Value<double> price;
  final Value<int?> componentGroupId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const ComponentsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.price = const Value.absent(),
    this.componentGroupId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ComponentsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.description = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.price = const Value.absent(),
    this.componentGroupId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Component> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? imageUrl,
    Expression<double>? price,
    Expression<int>? componentGroupId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (imageUrl != null) 'image_url': imageUrl,
      if (price != null) 'price': price,
      if (componentGroupId != null) 'component_group_id': componentGroupId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ComponentsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<String?>? imageUrl,
    Value<double>? price,
    Value<int?>? componentGroupId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return ComponentsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      price: price ?? this.price,
      componentGroupId: componentGroupId ?? this.componentGroupId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (componentGroupId.present) {
      map['component_group_id'] = Variable<int>(componentGroupId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ComponentsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('price: $price, ')
          ..write('componentGroupId: $componentGroupId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ComponentGroupsTable extends ComponentGroups
    with TableInfo<$ComponentGroupsTable, ComponentGroup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ComponentGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayOrderMeta = const VerificationMeta(
    'displayOrder',
  );
  @override
  late final GeneratedColumn<int> displayOrder = GeneratedColumn<int>(
    'display_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    displayOrder,
    description,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'component_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<ComponentGroup> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('display_order')) {
      context.handle(
        _displayOrderMeta,
        displayOrder.isAcceptableOrUnknown(
          data['display_order']!,
          _displayOrderMeta,
        ),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ComponentGroup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ComponentGroup(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      displayOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}display_order'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ComponentGroupsTable createAlias(String alias) {
    return $ComponentGroupsTable(attachedDatabase, alias);
  }
}

class ComponentGroup extends DataClass implements Insertable<ComponentGroup> {
  final int id;
  final String name;
  final int displayOrder;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ComponentGroup({
    required this.id,
    required this.name,
    required this.displayOrder,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['display_order'] = Variable<int>(displayOrder);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ComponentGroupsCompanion toCompanion(bool nullToAbsent) {
    return ComponentGroupsCompanion(
      id: Value(id),
      name: Value(name),
      displayOrder: Value(displayOrder),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ComponentGroup.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ComponentGroup(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      displayOrder: serializer.fromJson<int>(json['displayOrder']),
      description: serializer.fromJson<String?>(json['description']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'displayOrder': serializer.toJson<int>(displayOrder),
      'description': serializer.toJson<String?>(description),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ComponentGroup copyWith({
    int? id,
    String? name,
    int? displayOrder,
    Value<String?> description = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ComponentGroup(
    id: id ?? this.id,
    name: name ?? this.name,
    displayOrder: displayOrder ?? this.displayOrder,
    description: description.present ? description.value : this.description,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ComponentGroup copyWithCompanion(ComponentGroupsCompanion data) {
    return ComponentGroup(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      displayOrder: data.displayOrder.present
          ? data.displayOrder.value
          : this.displayOrder,
      description: data.description.present
          ? data.description.value
          : this.description,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ComponentGroup(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, displayOrder, description, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ComponentGroup &&
          other.id == this.id &&
          other.name == this.name &&
          other.displayOrder == this.displayOrder &&
          other.description == this.description &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ComponentGroupsCompanion extends UpdateCompanion<ComponentGroup> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> displayOrder;
  final Value<String?> description;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const ComponentGroupsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ComponentGroupsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.displayOrder = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<ComponentGroup> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? displayOrder,
    Expression<String>? description,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (displayOrder != null) 'display_order': displayOrder,
      if (description != null) 'description': description,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ComponentGroupsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? displayOrder,
    Value<String?>? description,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return ComponentGroupsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      displayOrder: displayOrder ?? this.displayOrder,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (displayOrder.present) {
      map['display_order'] = Variable<int>(displayOrder.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ComponentGroupsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ProductComponentsTable extends ProductComponents
    with TableInfo<$ProductComponentsTable, ProductComponent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductComponentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<int> productId = GeneratedColumn<int>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _componentIdMeta = const VerificationMeta(
    'componentId',
  );
  @override
  late final GeneratedColumn<int> componentId = GeneratedColumn<int>(
    'component_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _defaultPriceMeta = const VerificationMeta(
    'defaultPrice',
  );
  @override
  late final GeneratedColumn<double> defaultPrice = GeneratedColumn<double>(
    'default_price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _defaultQuantityMeta = const VerificationMeta(
    'defaultQuantity',
  );
  @override
  late final GeneratedColumn<int> defaultQuantity = GeneratedColumn<int>(
    'default_quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isRequiredMeta = const VerificationMeta(
    'isRequired',
  );
  @override
  late final GeneratedColumn<bool> isRequired = GeneratedColumn<bool>(
    'is_required',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_required" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _minQuantityMeta = const VerificationMeta(
    'minQuantity',
  );
  @override
  late final GeneratedColumn<int> minQuantity = GeneratedColumn<int>(
    'min_quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _maxQuantityMeta = const VerificationMeta(
    'maxQuantity',
  );
  @override
  late final GeneratedColumn<int> maxQuantity = GeneratedColumn<int>(
    'max_quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(10),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    productId,
    componentId,
    defaultPrice,
    defaultQuantity,
    isRequired,
    minQuantity,
    maxQuantity,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_components';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProductComponent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('component_id')) {
      context.handle(
        _componentIdMeta,
        componentId.isAcceptableOrUnknown(
          data['component_id']!,
          _componentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_componentIdMeta);
    }
    if (data.containsKey('default_price')) {
      context.handle(
        _defaultPriceMeta,
        defaultPrice.isAcceptableOrUnknown(
          data['default_price']!,
          _defaultPriceMeta,
        ),
      );
    }
    if (data.containsKey('default_quantity')) {
      context.handle(
        _defaultQuantityMeta,
        defaultQuantity.isAcceptableOrUnknown(
          data['default_quantity']!,
          _defaultQuantityMeta,
        ),
      );
    }
    if (data.containsKey('is_required')) {
      context.handle(
        _isRequiredMeta,
        isRequired.isAcceptableOrUnknown(data['is_required']!, _isRequiredMeta),
      );
    }
    if (data.containsKey('min_quantity')) {
      context.handle(
        _minQuantityMeta,
        minQuantity.isAcceptableOrUnknown(
          data['min_quantity']!,
          _minQuantityMeta,
        ),
      );
    }
    if (data.containsKey('max_quantity')) {
      context.handle(
        _maxQuantityMeta,
        maxQuantity.isAcceptableOrUnknown(
          data['max_quantity']!,
          _maxQuantityMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductComponent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductComponent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}product_id'],
      )!,
      componentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}component_id'],
      )!,
      defaultPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}default_price'],
      )!,
      defaultQuantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}default_quantity'],
      )!,
      isRequired: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_required'],
      )!,
      minQuantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}min_quantity'],
      )!,
      maxQuantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_quantity'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProductComponentsTable createAlias(String alias) {
    return $ProductComponentsTable(attachedDatabase, alias);
  }
}

class ProductComponent extends DataClass
    implements Insertable<ProductComponent> {
  final int id;
  final int productId;
  final int componentId;
  final double defaultPrice;
  final int defaultQuantity;
  final bool isRequired;
  final int minQuantity;
  final int maxQuantity;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ProductComponent({
    required this.id,
    required this.productId,
    required this.componentId,
    required this.defaultPrice,
    required this.defaultQuantity,
    required this.isRequired,
    required this.minQuantity,
    required this.maxQuantity,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['product_id'] = Variable<int>(productId);
    map['component_id'] = Variable<int>(componentId);
    map['default_price'] = Variable<double>(defaultPrice);
    map['default_quantity'] = Variable<int>(defaultQuantity);
    map['is_required'] = Variable<bool>(isRequired);
    map['min_quantity'] = Variable<int>(minQuantity);
    map['max_quantity'] = Variable<int>(maxQuantity);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProductComponentsCompanion toCompanion(bool nullToAbsent) {
    return ProductComponentsCompanion(
      id: Value(id),
      productId: Value(productId),
      componentId: Value(componentId),
      defaultPrice: Value(defaultPrice),
      defaultQuantity: Value(defaultQuantity),
      isRequired: Value(isRequired),
      minQuantity: Value(minQuantity),
      maxQuantity: Value(maxQuantity),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProductComponent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductComponent(
      id: serializer.fromJson<int>(json['id']),
      productId: serializer.fromJson<int>(json['productId']),
      componentId: serializer.fromJson<int>(json['componentId']),
      defaultPrice: serializer.fromJson<double>(json['defaultPrice']),
      defaultQuantity: serializer.fromJson<int>(json['defaultQuantity']),
      isRequired: serializer.fromJson<bool>(json['isRequired']),
      minQuantity: serializer.fromJson<int>(json['minQuantity']),
      maxQuantity: serializer.fromJson<int>(json['maxQuantity']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'productId': serializer.toJson<int>(productId),
      'componentId': serializer.toJson<int>(componentId),
      'defaultPrice': serializer.toJson<double>(defaultPrice),
      'defaultQuantity': serializer.toJson<int>(defaultQuantity),
      'isRequired': serializer.toJson<bool>(isRequired),
      'minQuantity': serializer.toJson<int>(minQuantity),
      'maxQuantity': serializer.toJson<int>(maxQuantity),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ProductComponent copyWith({
    int? id,
    int? productId,
    int? componentId,
    double? defaultPrice,
    int? defaultQuantity,
    bool? isRequired,
    int? minQuantity,
    int? maxQuantity,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ProductComponent(
    id: id ?? this.id,
    productId: productId ?? this.productId,
    componentId: componentId ?? this.componentId,
    defaultPrice: defaultPrice ?? this.defaultPrice,
    defaultQuantity: defaultQuantity ?? this.defaultQuantity,
    isRequired: isRequired ?? this.isRequired,
    minQuantity: minQuantity ?? this.minQuantity,
    maxQuantity: maxQuantity ?? this.maxQuantity,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ProductComponent copyWithCompanion(ProductComponentsCompanion data) {
    return ProductComponent(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      componentId: data.componentId.present
          ? data.componentId.value
          : this.componentId,
      defaultPrice: data.defaultPrice.present
          ? data.defaultPrice.value
          : this.defaultPrice,
      defaultQuantity: data.defaultQuantity.present
          ? data.defaultQuantity.value
          : this.defaultQuantity,
      isRequired: data.isRequired.present
          ? data.isRequired.value
          : this.isRequired,
      minQuantity: data.minQuantity.present
          ? data.minQuantity.value
          : this.minQuantity,
      maxQuantity: data.maxQuantity.present
          ? data.maxQuantity.value
          : this.maxQuantity,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductComponent(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('componentId: $componentId, ')
          ..write('defaultPrice: $defaultPrice, ')
          ..write('defaultQuantity: $defaultQuantity, ')
          ..write('isRequired: $isRequired, ')
          ..write('minQuantity: $minQuantity, ')
          ..write('maxQuantity: $maxQuantity, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    productId,
    componentId,
    defaultPrice,
    defaultQuantity,
    isRequired,
    minQuantity,
    maxQuantity,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductComponent &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.componentId == this.componentId &&
          other.defaultPrice == this.defaultPrice &&
          other.defaultQuantity == this.defaultQuantity &&
          other.isRequired == this.isRequired &&
          other.minQuantity == this.minQuantity &&
          other.maxQuantity == this.maxQuantity &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProductComponentsCompanion extends UpdateCompanion<ProductComponent> {
  final Value<int> id;
  final Value<int> productId;
  final Value<int> componentId;
  final Value<double> defaultPrice;
  final Value<int> defaultQuantity;
  final Value<bool> isRequired;
  final Value<int> minQuantity;
  final Value<int> maxQuantity;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const ProductComponentsCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.componentId = const Value.absent(),
    this.defaultPrice = const Value.absent(),
    this.defaultQuantity = const Value.absent(),
    this.isRequired = const Value.absent(),
    this.minQuantity = const Value.absent(),
    this.maxQuantity = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ProductComponentsCompanion.insert({
    this.id = const Value.absent(),
    required int productId,
    required int componentId,
    this.defaultPrice = const Value.absent(),
    this.defaultQuantity = const Value.absent(),
    this.isRequired = const Value.absent(),
    this.minQuantity = const Value.absent(),
    this.maxQuantity = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : productId = Value(productId),
       componentId = Value(componentId);
  static Insertable<ProductComponent> custom({
    Expression<int>? id,
    Expression<int>? productId,
    Expression<int>? componentId,
    Expression<double>? defaultPrice,
    Expression<int>? defaultQuantity,
    Expression<bool>? isRequired,
    Expression<int>? minQuantity,
    Expression<int>? maxQuantity,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (componentId != null) 'component_id': componentId,
      if (defaultPrice != null) 'default_price': defaultPrice,
      if (defaultQuantity != null) 'default_quantity': defaultQuantity,
      if (isRequired != null) 'is_required': isRequired,
      if (minQuantity != null) 'min_quantity': minQuantity,
      if (maxQuantity != null) 'max_quantity': maxQuantity,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ProductComponentsCompanion copyWith({
    Value<int>? id,
    Value<int>? productId,
    Value<int>? componentId,
    Value<double>? defaultPrice,
    Value<int>? defaultQuantity,
    Value<bool>? isRequired,
    Value<int>? minQuantity,
    Value<int>? maxQuantity,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return ProductComponentsCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      componentId: componentId ?? this.componentId,
      defaultPrice: defaultPrice ?? this.defaultPrice,
      defaultQuantity: defaultQuantity ?? this.defaultQuantity,
      isRequired: isRequired ?? this.isRequired,
      minQuantity: minQuantity ?? this.minQuantity,
      maxQuantity: maxQuantity ?? this.maxQuantity,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<int>(productId.value);
    }
    if (componentId.present) {
      map['component_id'] = Variable<int>(componentId.value);
    }
    if (defaultPrice.present) {
      map['default_price'] = Variable<double>(defaultPrice.value);
    }
    if (defaultQuantity.present) {
      map['default_quantity'] = Variable<int>(defaultQuantity.value);
    }
    if (isRequired.present) {
      map['is_required'] = Variable<bool>(isRequired.value);
    }
    if (minQuantity.present) {
      map['min_quantity'] = Variable<int>(minQuantity.value);
    }
    if (maxQuantity.present) {
      map['max_quantity'] = Variable<int>(maxQuantity.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductComponentsCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('componentId: $componentId, ')
          ..write('defaultPrice: $defaultPrice, ')
          ..write('defaultQuantity: $defaultQuantity, ')
          ..write('isRequired: $isRequired, ')
          ..write('minQuantity: $minQuantity, ')
          ..write('maxQuantity: $maxQuantity, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $AreasTable extends Areas with TableInfo<$AreasTable, Area> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AreasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'areas';
  @override
  VerificationContext validateIntegrity(
    Insertable<Area> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Area map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Area(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $AreasTable createAlias(String alias) {
    return $AreasTable(attachedDatabase, alias);
  }
}

class Area extends DataClass implements Insertable<Area> {
  final int id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Area({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AreasCompanion toCompanion(bool nullToAbsent) {
    return AreasCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Area.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Area(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Area copyWith({
    int? id,
    String? name,
    Value<String?> description = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Area(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Area copyWithCompanion(AreasCompanion data) {
    return Area(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Area(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, description, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Area &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class AreasCompanion extends UpdateCompanion<Area> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const AreasCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  AreasCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Area> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  AreasCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return AreasCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AreasCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $AreaTablesTable extends AreaTables
    with TableInfo<$AreaTablesTable, AreaTable> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AreaTablesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tableStateMeta = const VerificationMeta(
    'tableState',
  );
  @override
  late final GeneratedColumn<String> tableState = GeneratedColumn<String>(
    'table_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('AVAILABLE'),
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _capacityMeta = const VerificationMeta(
    'capacity',
  );
  @override
  late final GeneratedColumn<int> capacity = GeneratedColumn<int>(
    'capacity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(4),
  );
  static const VerificationMeta _areaIdMeta = const VerificationMeta('areaId');
  @override
  late final GeneratedColumn<int> areaId = GeneratedColumn<int>(
    'area_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _orderIdMeta = const VerificationMeta(
    'orderId',
  );
  @override
  late final GeneratedColumn<int> orderId = GeneratedColumn<int>(
    'order_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    tableState,
    description,
    capacity,
    areaId,
    createdAt,
    updatedAt,
    orderId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'area_tables';
  @override
  VerificationContext validateIntegrity(
    Insertable<AreaTable> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('table_state')) {
      context.handle(
        _tableStateMeta,
        tableState.isAcceptableOrUnknown(data['table_state']!, _tableStateMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('capacity')) {
      context.handle(
        _capacityMeta,
        capacity.isAcceptableOrUnknown(data['capacity']!, _capacityMeta),
      );
    }
    if (data.containsKey('area_id')) {
      context.handle(
        _areaIdMeta,
        areaId.isAcceptableOrUnknown(data['area_id']!, _areaIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('order_id')) {
      context.handle(
        _orderIdMeta,
        orderId.isAcceptableOrUnknown(data['order_id']!, _orderIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AreaTable map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AreaTable(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      tableState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}table_state'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      capacity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}capacity'],
      )!,
      areaId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}area_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      orderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_id'],
      ),
    );
  }

  @override
  $AreaTablesTable createAlias(String alias) {
    return $AreaTablesTable(attachedDatabase, alias);
  }
}

class AreaTable extends DataClass implements Insertable<AreaTable> {
  final int id;
  final String name;
  final String tableState;
  final String? description;
  final int capacity;
  final int? areaId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int? orderId;
  const AreaTable({
    required this.id,
    required this.name,
    required this.tableState,
    this.description,
    required this.capacity,
    this.areaId,
    required this.createdAt,
    required this.updatedAt,
    this.orderId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['table_state'] = Variable<String>(tableState);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['capacity'] = Variable<int>(capacity);
    if (!nullToAbsent || areaId != null) {
      map['area_id'] = Variable<int>(areaId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || orderId != null) {
      map['order_id'] = Variable<int>(orderId);
    }
    return map;
  }

  AreaTablesCompanion toCompanion(bool nullToAbsent) {
    return AreaTablesCompanion(
      id: Value(id),
      name: Value(name),
      tableState: Value(tableState),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      capacity: Value(capacity),
      areaId: areaId == null && nullToAbsent
          ? const Value.absent()
          : Value(areaId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      orderId: orderId == null && nullToAbsent
          ? const Value.absent()
          : Value(orderId),
    );
  }

  factory AreaTable.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AreaTable(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      tableState: serializer.fromJson<String>(json['tableState']),
      description: serializer.fromJson<String?>(json['description']),
      capacity: serializer.fromJson<int>(json['capacity']),
      areaId: serializer.fromJson<int?>(json['areaId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      orderId: serializer.fromJson<int?>(json['orderId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'tableState': serializer.toJson<String>(tableState),
      'description': serializer.toJson<String?>(description),
      'capacity': serializer.toJson<int>(capacity),
      'areaId': serializer.toJson<int?>(areaId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'orderId': serializer.toJson<int?>(orderId),
    };
  }

  AreaTable copyWith({
    int? id,
    String? name,
    String? tableState,
    Value<String?> description = const Value.absent(),
    int? capacity,
    Value<int?> areaId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<int?> orderId = const Value.absent(),
  }) => AreaTable(
    id: id ?? this.id,
    name: name ?? this.name,
    tableState: tableState ?? this.tableState,
    description: description.present ? description.value : this.description,
    capacity: capacity ?? this.capacity,
    areaId: areaId.present ? areaId.value : this.areaId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    orderId: orderId.present ? orderId.value : this.orderId,
  );
  AreaTable copyWithCompanion(AreaTablesCompanion data) {
    return AreaTable(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      tableState: data.tableState.present
          ? data.tableState.value
          : this.tableState,
      description: data.description.present
          ? data.description.value
          : this.description,
      capacity: data.capacity.present ? data.capacity.value : this.capacity,
      areaId: data.areaId.present ? data.areaId.value : this.areaId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      orderId: data.orderId.present ? data.orderId.value : this.orderId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AreaTable(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('tableState: $tableState, ')
          ..write('description: $description, ')
          ..write('capacity: $capacity, ')
          ..write('areaId: $areaId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('orderId: $orderId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    tableState,
    description,
    capacity,
    areaId,
    createdAt,
    updatedAt,
    orderId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AreaTable &&
          other.id == this.id &&
          other.name == this.name &&
          other.tableState == this.tableState &&
          other.description == this.description &&
          other.capacity == this.capacity &&
          other.areaId == this.areaId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.orderId == this.orderId);
}

class AreaTablesCompanion extends UpdateCompanion<AreaTable> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> tableState;
  final Value<String?> description;
  final Value<int> capacity;
  final Value<int?> areaId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int?> orderId;
  const AreaTablesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.tableState = const Value.absent(),
    this.description = const Value.absent(),
    this.capacity = const Value.absent(),
    this.areaId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.orderId = const Value.absent(),
  });
  AreaTablesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.tableState = const Value.absent(),
    this.description = const Value.absent(),
    this.capacity = const Value.absent(),
    this.areaId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.orderId = const Value.absent(),
  }) : name = Value(name);
  static Insertable<AreaTable> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? tableState,
    Expression<String>? description,
    Expression<int>? capacity,
    Expression<int>? areaId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? orderId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (tableState != null) 'table_state': tableState,
      if (description != null) 'description': description,
      if (capacity != null) 'capacity': capacity,
      if (areaId != null) 'area_id': areaId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (orderId != null) 'order_id': orderId,
    });
  }

  AreaTablesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? tableState,
    Value<String?>? description,
    Value<int>? capacity,
    Value<int?>? areaId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int?>? orderId,
  }) {
    return AreaTablesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      tableState: tableState ?? this.tableState,
      description: description ?? this.description,
      capacity: capacity ?? this.capacity,
      areaId: areaId ?? this.areaId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      orderId: orderId ?? this.orderId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (tableState.present) {
      map['table_state'] = Variable<String>(tableState.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (capacity.present) {
      map['capacity'] = Variable<int>(capacity.value);
    }
    if (areaId.present) {
      map['area_id'] = Variable<int>(areaId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (orderId.present) {
      map['order_id'] = Variable<int>(orderId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AreaTablesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('tableState: $tableState, ')
          ..write('description: $description, ')
          ..write('capacity: $capacity, ')
          ..write('areaId: $areaId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('orderId: $orderId')
          ..write(')'))
        .toString();
  }
}

class $StationsTable extends Stations with TableInfo<$StationsTable, Station> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Station> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Station map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Station(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $StationsTable createAlias(String alias) {
    return $StationsTable(attachedDatabase, alias);
  }
}

class Station extends DataClass implements Insertable<Station> {
  final int id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Station({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  StationsCompanion toCompanion(bool nullToAbsent) {
    return StationsCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Station.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Station(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Station copyWith({
    int? id,
    String? name,
    Value<String?> description = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Station(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Station copyWithCompanion(StationsCompanion data) {
    return Station(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Station(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, description, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Station &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class StationsCompanion extends UpdateCompanion<Station> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const StationsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  StationsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.description = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Station> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  StationsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return StationsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StationsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $KiosksTable extends Kiosks with TableInfo<$KiosksTable, Kiosk> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KiosksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ipMeta = const VerificationMeta('ip');
  @override
  late final GeneratedColumn<String> ip = GeneratedColumn<String>(
    'ip',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    ip,
    port,
    location,
    isActive,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kiosks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Kiosk> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('ip')) {
      context.handle(_ipMeta, ip.isAcceptableOrUnknown(data['ip']!, _ipMeta));
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Kiosk map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Kiosk(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      ip: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ip'],
      ),
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      ),
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $KiosksTable createAlias(String alias) {
    return $KiosksTable(attachedDatabase, alias);
  }
}

class Kiosk extends DataClass implements Insertable<Kiosk> {
  final int id;
  final String name;
  final String? description;
  final String? ip;
  final int? port;
  final String? location;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Kiosk({
    required this.id,
    required this.name,
    this.description,
    this.ip,
    this.port,
    this.location,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || ip != null) {
      map['ip'] = Variable<String>(ip);
    }
    if (!nullToAbsent || port != null) {
      map['port'] = Variable<int>(port);
    }
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  KiosksCompanion toCompanion(bool nullToAbsent) {
    return KiosksCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      ip: ip == null && nullToAbsent ? const Value.absent() : Value(ip),
      port: port == null && nullToAbsent ? const Value.absent() : Value(port),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Kiosk.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Kiosk(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      ip: serializer.fromJson<String?>(json['ip']),
      port: serializer.fromJson<int?>(json['port']),
      location: serializer.fromJson<String?>(json['location']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'ip': serializer.toJson<String?>(ip),
      'port': serializer.toJson<int?>(port),
      'location': serializer.toJson<String?>(location),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Kiosk copyWith({
    int? id,
    String? name,
    Value<String?> description = const Value.absent(),
    Value<String?> ip = const Value.absent(),
    Value<int?> port = const Value.absent(),
    Value<String?> location = const Value.absent(),
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Kiosk(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    ip: ip.present ? ip.value : this.ip,
    port: port.present ? port.value : this.port,
    location: location.present ? location.value : this.location,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Kiosk copyWithCompanion(KiosksCompanion data) {
    return Kiosk(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      ip: data.ip.present ? data.ip.value : this.ip,
      port: data.port.present ? data.port.value : this.port,
      location: data.location.present ? data.location.value : this.location,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Kiosk(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('ip: $ip, ')
          ..write('port: $port, ')
          ..write('location: $location, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    ip,
    port,
    location,
    isActive,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Kiosk &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.ip == this.ip &&
          other.port == this.port &&
          other.location == this.location &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class KiosksCompanion extends UpdateCompanion<Kiosk> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<String?> ip;
  final Value<int?> port;
  final Value<String?> location;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const KiosksCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.ip = const Value.absent(),
    this.port = const Value.absent(),
    this.location = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  KiosksCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.description = const Value.absent(),
    this.ip = const Value.absent(),
    this.port = const Value.absent(),
    this.location = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Kiosk> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? ip,
    Expression<int>? port,
    Expression<String>? location,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (ip != null) 'ip': ip,
      if (port != null) 'port': port,
      if (location != null) 'location': location,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  KiosksCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<String?>? ip,
    Value<int?>? port,
    Value<String?>? location,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return KiosksCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      location: location ?? this.location,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (ip.present) {
      map['ip'] = Variable<String>(ip.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KiosksCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('ip: $ip, ')
          ..write('port: $port, ')
          ..write('location: $location, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $KDSsTable extends KDSs with TableInfo<$KDSsTable, KDS> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KDSsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stationIdMeta = const VerificationMeta(
    'stationId',
  );
  @override
  late final GeneratedColumn<int> stationId = GeneratedColumn<int>(
    'station_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ipMeta = const VerificationMeta('ip');
  @override
  late final GeneratedColumn<String> ip = GeneratedColumn<String>(
    'ip',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    stationId,
    ip,
    port,
    location,
    isActive,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'k_d_ss';
  @override
  VerificationContext validateIntegrity(
    Insertable<KDS> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('station_id')) {
      context.handle(
        _stationIdMeta,
        stationId.isAcceptableOrUnknown(data['station_id']!, _stationIdMeta),
      );
    }
    if (data.containsKey('ip')) {
      context.handle(_ipMeta, ip.isAcceptableOrUnknown(data['ip']!, _ipMeta));
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  KDS map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KDS(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      stationId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}station_id'],
      ),
      ip: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ip'],
      ),
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      ),
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $KDSsTable createAlias(String alias) {
    return $KDSsTable(attachedDatabase, alias);
  }
}

class KDS extends DataClass implements Insertable<KDS> {
  final int id;
  final String name;
  final String? description;
  final int? stationId;
  final String? ip;
  final int? port;
  final String? location;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  const KDS({
    required this.id,
    required this.name,
    this.description,
    this.stationId,
    this.ip,
    this.port,
    this.location,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || stationId != null) {
      map['station_id'] = Variable<int>(stationId);
    }
    if (!nullToAbsent || ip != null) {
      map['ip'] = Variable<String>(ip);
    }
    if (!nullToAbsent || port != null) {
      map['port'] = Variable<int>(port);
    }
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  KDSsCompanion toCompanion(bool nullToAbsent) {
    return KDSsCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      stationId: stationId == null && nullToAbsent
          ? const Value.absent()
          : Value(stationId),
      ip: ip == null && nullToAbsent ? const Value.absent() : Value(ip),
      port: port == null && nullToAbsent ? const Value.absent() : Value(port),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory KDS.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KDS(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      stationId: serializer.fromJson<int?>(json['stationId']),
      ip: serializer.fromJson<String?>(json['ip']),
      port: serializer.fromJson<int?>(json['port']),
      location: serializer.fromJson<String?>(json['location']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'stationId': serializer.toJson<int?>(stationId),
      'ip': serializer.toJson<String?>(ip),
      'port': serializer.toJson<int?>(port),
      'location': serializer.toJson<String?>(location),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  KDS copyWith({
    int? id,
    String? name,
    Value<String?> description = const Value.absent(),
    Value<int?> stationId = const Value.absent(),
    Value<String?> ip = const Value.absent(),
    Value<int?> port = const Value.absent(),
    Value<String?> location = const Value.absent(),
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => KDS(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    stationId: stationId.present ? stationId.value : this.stationId,
    ip: ip.present ? ip.value : this.ip,
    port: port.present ? port.value : this.port,
    location: location.present ? location.value : this.location,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  KDS copyWithCompanion(KDSsCompanion data) {
    return KDS(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      stationId: data.stationId.present ? data.stationId.value : this.stationId,
      ip: data.ip.present ? data.ip.value : this.ip,
      port: data.port.present ? data.port.value : this.port,
      location: data.location.present ? data.location.value : this.location,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KDS(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('stationId: $stationId, ')
          ..write('ip: $ip, ')
          ..write('port: $port, ')
          ..write('location: $location, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    stationId,
    ip,
    port,
    location,
    isActive,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KDS &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.stationId == this.stationId &&
          other.ip == this.ip &&
          other.port == this.port &&
          other.location == this.location &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class KDSsCompanion extends UpdateCompanion<KDS> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<int?> stationId;
  final Value<String?> ip;
  final Value<int?> port;
  final Value<String?> location;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const KDSsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.stationId = const Value.absent(),
    this.ip = const Value.absent(),
    this.port = const Value.absent(),
    this.location = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  KDSsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.description = const Value.absent(),
    this.stationId = const Value.absent(),
    this.ip = const Value.absent(),
    this.port = const Value.absent(),
    this.location = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<KDS> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<int>? stationId,
    Expression<String>? ip,
    Expression<int>? port,
    Expression<String>? location,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (stationId != null) 'station_id': stationId,
      if (ip != null) 'ip': ip,
      if (port != null) 'port': port,
      if (location != null) 'location': location,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  KDSsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<int?>? stationId,
    Value<String?>? ip,
    Value<int?>? port,
    Value<String?>? location,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return KDSsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      stationId: stationId ?? this.stationId,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      location: location ?? this.location,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (stationId.present) {
      map['station_id'] = Variable<int>(stationId.value);
    }
    if (ip.present) {
      map['ip'] = Variable<String>(ip.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KDSsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('stationId: $stationId, ')
          ..write('ip: $ip, ')
          ..write('port: $port, ')
          ..write('location: $location, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $CommercialsTable extends Commercials
    with TableInfo<$CommercialsTable, Commercial> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CommercialsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cinMeta = const VerificationMeta('cin');
  @override
  late final GeneratedColumn<String> cin = GeneratedColumn<String>(
    'cin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _firstNameMeta = const VerificationMeta(
    'firstName',
  );
  @override
  late final GeneratedColumn<String> firstName = GeneratedColumn<String>(
    'first_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastNameMeta = const VerificationMeta(
    'lastName',
  );
  @override
  late final GeneratedColumn<String> lastName = GeneratedColumn<String>(
    'last_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cin,
    firstName,
    lastName,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'commercials';
  @override
  VerificationContext validateIntegrity(
    Insertable<Commercial> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cin')) {
      context.handle(
        _cinMeta,
        cin.isAcceptableOrUnknown(data['cin']!, _cinMeta),
      );
    } else if (isInserting) {
      context.missing(_cinMeta);
    }
    if (data.containsKey('first_name')) {
      context.handle(
        _firstNameMeta,
        firstName.isAcceptableOrUnknown(data['first_name']!, _firstNameMeta),
      );
    } else if (isInserting) {
      context.missing(_firstNameMeta);
    }
    if (data.containsKey('last_name')) {
      context.handle(
        _lastNameMeta,
        lastName.isAcceptableOrUnknown(data['last_name']!, _lastNameMeta),
      );
    } else if (isInserting) {
      context.missing(_lastNameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Commercial map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Commercial(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      cin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cin'],
      )!,
      firstName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_name'],
      )!,
      lastName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CommercialsTable createAlias(String alias) {
    return $CommercialsTable(attachedDatabase, alias);
  }
}

class Commercial extends DataClass implements Insertable<Commercial> {
  final int id;
  final String cin;
  final String firstName;
  final String lastName;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Commercial({
    required this.id,
    required this.cin,
    required this.firstName,
    required this.lastName,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['cin'] = Variable<String>(cin);
    map['first_name'] = Variable<String>(firstName);
    map['last_name'] = Variable<String>(lastName);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CommercialsCompanion toCompanion(bool nullToAbsent) {
    return CommercialsCompanion(
      id: Value(id),
      cin: Value(cin),
      firstName: Value(firstName),
      lastName: Value(lastName),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Commercial.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Commercial(
      id: serializer.fromJson<int>(json['id']),
      cin: serializer.fromJson<String>(json['cin']),
      firstName: serializer.fromJson<String>(json['firstName']),
      lastName: serializer.fromJson<String>(json['lastName']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cin': serializer.toJson<String>(cin),
      'firstName': serializer.toJson<String>(firstName),
      'lastName': serializer.toJson<String>(lastName),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Commercial copyWith({
    int? id,
    String? cin,
    String? firstName,
    String? lastName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Commercial(
    id: id ?? this.id,
    cin: cin ?? this.cin,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Commercial copyWithCompanion(CommercialsCompanion data) {
    return Commercial(
      id: data.id.present ? data.id.value : this.id,
      cin: data.cin.present ? data.cin.value : this.cin,
      firstName: data.firstName.present ? data.firstName.value : this.firstName,
      lastName: data.lastName.present ? data.lastName.value : this.lastName,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Commercial(')
          ..write('id: $id, ')
          ..write('cin: $cin, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, cin, firstName, lastName, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Commercial &&
          other.id == this.id &&
          other.cin == this.cin &&
          other.firstName == this.firstName &&
          other.lastName == this.lastName &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CommercialsCompanion extends UpdateCompanion<Commercial> {
  final Value<int> id;
  final Value<String> cin;
  final Value<String> firstName;
  final Value<String> lastName;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const CommercialsCompanion({
    this.id = const Value.absent(),
    this.cin = const Value.absent(),
    this.firstName = const Value.absent(),
    this.lastName = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  CommercialsCompanion.insert({
    this.id = const Value.absent(),
    required String cin,
    required String firstName,
    required String lastName,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : cin = Value(cin),
       firstName = Value(firstName),
       lastName = Value(lastName);
  static Insertable<Commercial> custom({
    Expression<int>? id,
    Expression<String>? cin,
    Expression<String>? firstName,
    Expression<String>? lastName,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cin != null) 'cin': cin,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  CommercialsCompanion copyWith({
    Value<int>? id,
    Value<String>? cin,
    Value<String>? firstName,
    Value<String>? lastName,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return CommercialsCompanion(
      id: id ?? this.id,
      cin: cin ?? this.cin,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cin.present) {
      map['cin'] = Variable<String>(cin.value);
    }
    if (firstName.present) {
      map['first_name'] = Variable<String>(firstName.value);
    }
    if (lastName.present) {
      map['last_name'] = Variable<String>(lastName.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CommercialsCompanion(')
          ..write('id: $id, ')
          ..write('cin: $cin, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $CustomersTable extends Customers
    with TableInfo<$CustomersTable, Customer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _firstNameMeta = const VerificationMeta(
    'firstName',
  );
  @override
  late final GeneratedColumn<String> firstName = GeneratedColumn<String>(
    'first_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastNameMeta = const VerificationMeta(
    'lastName',
  );
  @override
  late final GeneratedColumn<String> lastName = GeneratedColumn<String>(
    'last_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isSyncedMeta = const VerificationMeta(
    'isSynced',
  );
  @override
  late final GeneratedColumn<bool> isSynced = GeneratedColumn<bool>(
    'is_synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    firstName,
    lastName,
    phone,
    email,
    isSynced,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'customers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Customer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('first_name')) {
      context.handle(
        _firstNameMeta,
        firstName.isAcceptableOrUnknown(data['first_name']!, _firstNameMeta),
      );
    } else if (isInserting) {
      context.missing(_firstNameMeta);
    }
    if (data.containsKey('last_name')) {
      context.handle(
        _lastNameMeta,
        lastName.isAcceptableOrUnknown(data['last_name']!, _lastNameMeta),
      );
    } else if (isInserting) {
      context.missing(_lastNameMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    if (data.containsKey('is_synced')) {
      context.handle(
        _isSyncedMeta,
        isSynced.isAcceptableOrUnknown(data['is_synced']!, _isSyncedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Customer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Customer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      firstName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_name'],
      )!,
      lastName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_name'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      ),
      isSynced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_synced'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CustomersTable createAlias(String alias) {
    return $CustomersTable(attachedDatabase, alias);
  }
}

class Customer extends DataClass implements Insertable<Customer> {
  final int id;
  final String firstName;
  final String lastName;
  final String? phone;
  final String? email;
  final bool isSynced;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Customer({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.phone,
    this.email,
    required this.isSynced,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['first_name'] = Variable<String>(firstName);
    map['last_name'] = Variable<String>(lastName);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    map['is_synced'] = Variable<bool>(isSynced);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CustomersCompanion toCompanion(bool nullToAbsent) {
    return CustomersCompanion(
      id: Value(id),
      firstName: Value(firstName),
      lastName: Value(lastName),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      email: email == null && nullToAbsent
          ? const Value.absent()
          : Value(email),
      isSynced: Value(isSynced),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Customer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Customer(
      id: serializer.fromJson<int>(json['id']),
      firstName: serializer.fromJson<String>(json['firstName']),
      lastName: serializer.fromJson<String>(json['lastName']),
      phone: serializer.fromJson<String?>(json['phone']),
      email: serializer.fromJson<String?>(json['email']),
      isSynced: serializer.fromJson<bool>(json['isSynced']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'firstName': serializer.toJson<String>(firstName),
      'lastName': serializer.toJson<String>(lastName),
      'phone': serializer.toJson<String?>(phone),
      'email': serializer.toJson<String?>(email),
      'isSynced': serializer.toJson<bool>(isSynced),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Customer copyWith({
    int? id,
    String? firstName,
    String? lastName,
    Value<String?> phone = const Value.absent(),
    Value<String?> email = const Value.absent(),
    bool? isSynced,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Customer(
    id: id ?? this.id,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    phone: phone.present ? phone.value : this.phone,
    email: email.present ? email.value : this.email,
    isSynced: isSynced ?? this.isSynced,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Customer copyWithCompanion(CustomersCompanion data) {
    return Customer(
      id: data.id.present ? data.id.value : this.id,
      firstName: data.firstName.present ? data.firstName.value : this.firstName,
      lastName: data.lastName.present ? data.lastName.value : this.lastName,
      phone: data.phone.present ? data.phone.value : this.phone,
      email: data.email.present ? data.email.value : this.email,
      isSynced: data.isSynced.present ? data.isSynced.value : this.isSynced,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Customer(')
          ..write('id: $id, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('phone: $phone, ')
          ..write('email: $email, ')
          ..write('isSynced: $isSynced, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    firstName,
    lastName,
    phone,
    email,
    isSynced,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Customer &&
          other.id == this.id &&
          other.firstName == this.firstName &&
          other.lastName == this.lastName &&
          other.phone == this.phone &&
          other.email == this.email &&
          other.isSynced == this.isSynced &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CustomersCompanion extends UpdateCompanion<Customer> {
  final Value<int> id;
  final Value<String> firstName;
  final Value<String> lastName;
  final Value<String?> phone;
  final Value<String?> email;
  final Value<bool> isSynced;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const CustomersCompanion({
    this.id = const Value.absent(),
    this.firstName = const Value.absent(),
    this.lastName = const Value.absent(),
    this.phone = const Value.absent(),
    this.email = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  CustomersCompanion.insert({
    this.id = const Value.absent(),
    required String firstName,
    required String lastName,
    this.phone = const Value.absent(),
    this.email = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : firstName = Value(firstName),
       lastName = Value(lastName);
  static Insertable<Customer> custom({
    Expression<int>? id,
    Expression<String>? firstName,
    Expression<String>? lastName,
    Expression<String>? phone,
    Expression<String>? email,
    Expression<bool>? isSynced,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (isSynced != null) 'is_synced': isSynced,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  CustomersCompanion copyWith({
    Value<int>? id,
    Value<String>? firstName,
    Value<String>? lastName,
    Value<String?>? phone,
    Value<String?>? email,
    Value<bool>? isSynced,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return CustomersCompanion(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      isSynced: isSynced ?? this.isSynced,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (firstName.present) {
      map['first_name'] = Variable<String>(firstName.value);
    }
    if (lastName.present) {
      map['last_name'] = Variable<String>(lastName.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (isSynced.present) {
      map['is_synced'] = Variable<bool>(isSynced.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomersCompanion(')
          ..write('id: $id, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('phone: $phone, ')
          ..write('email: $email, ')
          ..write('isSynced: $isSynced, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $OrdersTable extends Orders with TableInfo<$OrdersTable, Order> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OrdersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('ONHOLD'),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('DINE_IN'),
  );
  static const VerificationMeta _priorityMeta = const VerificationMeta(
    'priority',
  );
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
    'priority',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _couponMeta = const VerificationMeta('coupon');
  @override
  late final GeneratedColumn<String> coupon = GeneratedColumn<String>(
    'coupon',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _personsMeta = const VerificationMeta(
    'persons',
  );
  @override
  late final GeneratedColumn<int> persons = GeneratedColumn<int>(
    'persons',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _paymentIdMeta = const VerificationMeta(
    'paymentId',
  );
  @override
  late final GeneratedColumn<int> paymentId = GeneratedColumn<int>(
    'payment_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tableIdMeta = const VerificationMeta(
    'tableId',
  );
  @override
  late final GeneratedColumn<int> tableId = GeneratedColumn<int>(
    'table_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _discountPercentageMeta =
      const VerificationMeta('discountPercentage');
  @override
  late final GeneratedColumn<double> discountPercentage =
      GeneratedColumn<double>(
        'discount_percentage',
        aliasedName,
        false,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
        defaultValue: const Constant(0.0),
      );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<int> createdBy = GeneratedColumn<int>(
    'created_by',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _takenByMeta = const VerificationMeta(
    'takenBy',
  );
  @override
  late final GeneratedColumn<int> takenBy = GeneratedColumn<int>(
    'taken_by',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _waiterIdMeta = const VerificationMeta(
    'waiterId',
  );
  @override
  late final GeneratedColumn<int> waiterId = GeneratedColumn<int>(
    'waiter_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<int> clientId = GeneratedColumn<int>(
    'client_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _commercialIdMeta = const VerificationMeta(
    'commercialId',
  );
  @override
  late final GeneratedColumn<int> commercialId = GeneratedColumn<int>(
    'commercial_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _isSyncedMeta = const VerificationMeta(
    'isSynced',
  );
  @override
  late final GeneratedColumn<bool> isSynced = GeneratedColumn<bool>(
    'is_synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    code,
    status,
    type,
    priority,
    coupon,
    persons,
    date,
    paymentId,
    tableId,
    source,
    sourceId,
    discountPercentage,
    createdBy,
    takenBy,
    waiterId,
    clientId,
    commercialId,
    note,
    createdAt,
    updatedAt,
    isSynced,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'orders';
  @override
  VerificationContext validateIntegrity(
    Insertable<Order> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('priority')) {
      context.handle(
        _priorityMeta,
        priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta),
      );
    }
    if (data.containsKey('coupon')) {
      context.handle(
        _couponMeta,
        coupon.isAcceptableOrUnknown(data['coupon']!, _couponMeta),
      );
    }
    if (data.containsKey('persons')) {
      context.handle(
        _personsMeta,
        persons.isAcceptableOrUnknown(data['persons']!, _personsMeta),
      );
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    }
    if (data.containsKey('payment_id')) {
      context.handle(
        _paymentIdMeta,
        paymentId.isAcceptableOrUnknown(data['payment_id']!, _paymentIdMeta),
      );
    }
    if (data.containsKey('table_id')) {
      context.handle(
        _tableIdMeta,
        tableId.isAcceptableOrUnknown(data['table_id']!, _tableIdMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    }
    if (data.containsKey('discount_percentage')) {
      context.handle(
        _discountPercentageMeta,
        discountPercentage.isAcceptableOrUnknown(
          data['discount_percentage']!,
          _discountPercentageMeta,
        ),
      );
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    }
    if (data.containsKey('taken_by')) {
      context.handle(
        _takenByMeta,
        takenBy.isAcceptableOrUnknown(data['taken_by']!, _takenByMeta),
      );
    }
    if (data.containsKey('waiter_id')) {
      context.handle(
        _waiterIdMeta,
        waiterId.isAcceptableOrUnknown(data['waiter_id']!, _waiterIdMeta),
      );
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    }
    if (data.containsKey('commercial_id')) {
      context.handle(
        _commercialIdMeta,
        commercialId.isAcceptableOrUnknown(
          data['commercial_id']!,
          _commercialIdMeta,
        ),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('is_synced')) {
      context.handle(
        _isSyncedMeta,
        isSynced.isAcceptableOrUnknown(data['is_synced']!, _isSyncedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Order map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Order(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      priority: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}priority'],
      )!,
      coupon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}coupon'],
      ),
      persons: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}persons'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      paymentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payment_id'],
      ),
      tableId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}table_id'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      ),
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      ),
      discountPercentage: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}discount_percentage'],
      )!,
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_by'],
      ),
      takenBy: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}taken_by'],
      ),
      waiterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}waiter_id'],
      ),
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}client_id'],
      ),
      commercialId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}commercial_id'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isSynced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_synced'],
      )!,
    );
  }

  @override
  $OrdersTable createAlias(String alias) {
    return $OrdersTable(attachedDatabase, alias);
  }
}

class Order extends DataClass implements Insertable<Order> {
  final int id;
  final String code;
  final String status;
  final String type;
  final int priority;
  final String? coupon;
  final int persons;
  final DateTime date;
  final int? paymentId;
  final int? tableId;
  final String? source;
  final int? sourceId;
  final double discountPercentage;
  final int? createdBy;
  final int? takenBy;
  final int? waiterId;
  final int? clientId;
  final int? commercialId;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;
  const Order({
    required this.id,
    required this.code,
    required this.status,
    required this.type,
    required this.priority,
    this.coupon,
    required this.persons,
    required this.date,
    this.paymentId,
    this.tableId,
    this.source,
    this.sourceId,
    required this.discountPercentage,
    this.createdBy,
    this.takenBy,
    this.waiterId,
    this.clientId,
    this.commercialId,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    required this.isSynced,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['code'] = Variable<String>(code);
    map['status'] = Variable<String>(status);
    map['type'] = Variable<String>(type);
    map['priority'] = Variable<int>(priority);
    if (!nullToAbsent || coupon != null) {
      map['coupon'] = Variable<String>(coupon);
    }
    map['persons'] = Variable<int>(persons);
    map['date'] = Variable<DateTime>(date);
    if (!nullToAbsent || paymentId != null) {
      map['payment_id'] = Variable<int>(paymentId);
    }
    if (!nullToAbsent || tableId != null) {
      map['table_id'] = Variable<int>(tableId);
    }
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    if (!nullToAbsent || sourceId != null) {
      map['source_id'] = Variable<int>(sourceId);
    }
    map['discount_percentage'] = Variable<double>(discountPercentage);
    if (!nullToAbsent || createdBy != null) {
      map['created_by'] = Variable<int>(createdBy);
    }
    if (!nullToAbsent || takenBy != null) {
      map['taken_by'] = Variable<int>(takenBy);
    }
    if (!nullToAbsent || waiterId != null) {
      map['waiter_id'] = Variable<int>(waiterId);
    }
    if (!nullToAbsent || clientId != null) {
      map['client_id'] = Variable<int>(clientId);
    }
    if (!nullToAbsent || commercialId != null) {
      map['commercial_id'] = Variable<int>(commercialId);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_synced'] = Variable<bool>(isSynced);
    return map;
  }

  OrdersCompanion toCompanion(bool nullToAbsent) {
    return OrdersCompanion(
      id: Value(id),
      code: Value(code),
      status: Value(status),
      type: Value(type),
      priority: Value(priority),
      coupon: coupon == null && nullToAbsent
          ? const Value.absent()
          : Value(coupon),
      persons: Value(persons),
      date: Value(date),
      paymentId: paymentId == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentId),
      tableId: tableId == null && nullToAbsent
          ? const Value.absent()
          : Value(tableId),
      source: source == null && nullToAbsent
          ? const Value.absent()
          : Value(source),
      sourceId: sourceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceId),
      discountPercentage: Value(discountPercentage),
      createdBy: createdBy == null && nullToAbsent
          ? const Value.absent()
          : Value(createdBy),
      takenBy: takenBy == null && nullToAbsent
          ? const Value.absent()
          : Value(takenBy),
      waiterId: waiterId == null && nullToAbsent
          ? const Value.absent()
          : Value(waiterId),
      clientId: clientId == null && nullToAbsent
          ? const Value.absent()
          : Value(clientId),
      commercialId: commercialId == null && nullToAbsent
          ? const Value.absent()
          : Value(commercialId),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isSynced: Value(isSynced),
    );
  }

  factory Order.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Order(
      id: serializer.fromJson<int>(json['id']),
      code: serializer.fromJson<String>(json['code']),
      status: serializer.fromJson<String>(json['status']),
      type: serializer.fromJson<String>(json['type']),
      priority: serializer.fromJson<int>(json['priority']),
      coupon: serializer.fromJson<String?>(json['coupon']),
      persons: serializer.fromJson<int>(json['persons']),
      date: serializer.fromJson<DateTime>(json['date']),
      paymentId: serializer.fromJson<int?>(json['paymentId']),
      tableId: serializer.fromJson<int?>(json['tableId']),
      source: serializer.fromJson<String?>(json['source']),
      sourceId: serializer.fromJson<int?>(json['sourceId']),
      discountPercentage: serializer.fromJson<double>(
        json['discountPercentage'],
      ),
      createdBy: serializer.fromJson<int?>(json['createdBy']),
      takenBy: serializer.fromJson<int?>(json['takenBy']),
      waiterId: serializer.fromJson<int?>(json['waiterId']),
      clientId: serializer.fromJson<int?>(json['clientId']),
      commercialId: serializer.fromJson<int?>(json['commercialId']),
      note: serializer.fromJson<String?>(json['note']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isSynced: serializer.fromJson<bool>(json['isSynced']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'code': serializer.toJson<String>(code),
      'status': serializer.toJson<String>(status),
      'type': serializer.toJson<String>(type),
      'priority': serializer.toJson<int>(priority),
      'coupon': serializer.toJson<String?>(coupon),
      'persons': serializer.toJson<int>(persons),
      'date': serializer.toJson<DateTime>(date),
      'paymentId': serializer.toJson<int?>(paymentId),
      'tableId': serializer.toJson<int?>(tableId),
      'source': serializer.toJson<String?>(source),
      'sourceId': serializer.toJson<int?>(sourceId),
      'discountPercentage': serializer.toJson<double>(discountPercentage),
      'createdBy': serializer.toJson<int?>(createdBy),
      'takenBy': serializer.toJson<int?>(takenBy),
      'waiterId': serializer.toJson<int?>(waiterId),
      'clientId': serializer.toJson<int?>(clientId),
      'commercialId': serializer.toJson<int?>(commercialId),
      'note': serializer.toJson<String?>(note),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isSynced': serializer.toJson<bool>(isSynced),
    };
  }

  Order copyWith({
    int? id,
    String? code,
    String? status,
    String? type,
    int? priority,
    Value<String?> coupon = const Value.absent(),
    int? persons,
    DateTime? date,
    Value<int?> paymentId = const Value.absent(),
    Value<int?> tableId = const Value.absent(),
    Value<String?> source = const Value.absent(),
    Value<int?> sourceId = const Value.absent(),
    double? discountPercentage,
    Value<int?> createdBy = const Value.absent(),
    Value<int?> takenBy = const Value.absent(),
    Value<int?> waiterId = const Value.absent(),
    Value<int?> clientId = const Value.absent(),
    Value<int?> commercialId = const Value.absent(),
    Value<String?> note = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
  }) => Order(
    id: id ?? this.id,
    code: code ?? this.code,
    status: status ?? this.status,
    type: type ?? this.type,
    priority: priority ?? this.priority,
    coupon: coupon.present ? coupon.value : this.coupon,
    persons: persons ?? this.persons,
    date: date ?? this.date,
    paymentId: paymentId.present ? paymentId.value : this.paymentId,
    tableId: tableId.present ? tableId.value : this.tableId,
    source: source.present ? source.value : this.source,
    sourceId: sourceId.present ? sourceId.value : this.sourceId,
    discountPercentage: discountPercentage ?? this.discountPercentage,
    createdBy: createdBy.present ? createdBy.value : this.createdBy,
    takenBy: takenBy.present ? takenBy.value : this.takenBy,
    waiterId: waiterId.present ? waiterId.value : this.waiterId,
    clientId: clientId.present ? clientId.value : this.clientId,
    commercialId: commercialId.present ? commercialId.value : this.commercialId,
    note: note.present ? note.value : this.note,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isSynced: isSynced ?? this.isSynced,
  );
  Order copyWithCompanion(OrdersCompanion data) {
    return Order(
      id: data.id.present ? data.id.value : this.id,
      code: data.code.present ? data.code.value : this.code,
      status: data.status.present ? data.status.value : this.status,
      type: data.type.present ? data.type.value : this.type,
      priority: data.priority.present ? data.priority.value : this.priority,
      coupon: data.coupon.present ? data.coupon.value : this.coupon,
      persons: data.persons.present ? data.persons.value : this.persons,
      date: data.date.present ? data.date.value : this.date,
      paymentId: data.paymentId.present ? data.paymentId.value : this.paymentId,
      tableId: data.tableId.present ? data.tableId.value : this.tableId,
      source: data.source.present ? data.source.value : this.source,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      discountPercentage: data.discountPercentage.present
          ? data.discountPercentage.value
          : this.discountPercentage,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      takenBy: data.takenBy.present ? data.takenBy.value : this.takenBy,
      waiterId: data.waiterId.present ? data.waiterId.value : this.waiterId,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      commercialId: data.commercialId.present
          ? data.commercialId.value
          : this.commercialId,
      note: data.note.present ? data.note.value : this.note,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isSynced: data.isSynced.present ? data.isSynced.value : this.isSynced,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Order(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('status: $status, ')
          ..write('type: $type, ')
          ..write('priority: $priority, ')
          ..write('coupon: $coupon, ')
          ..write('persons: $persons, ')
          ..write('date: $date, ')
          ..write('paymentId: $paymentId, ')
          ..write('tableId: $tableId, ')
          ..write('source: $source, ')
          ..write('sourceId: $sourceId, ')
          ..write('discountPercentage: $discountPercentage, ')
          ..write('createdBy: $createdBy, ')
          ..write('takenBy: $takenBy, ')
          ..write('waiterId: $waiterId, ')
          ..write('clientId: $clientId, ')
          ..write('commercialId: $commercialId, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isSynced: $isSynced')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    code,
    status,
    type,
    priority,
    coupon,
    persons,
    date,
    paymentId,
    tableId,
    source,
    sourceId,
    discountPercentage,
    createdBy,
    takenBy,
    waiterId,
    clientId,
    commercialId,
    note,
    createdAt,
    updatedAt,
    isSynced,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Order &&
          other.id == this.id &&
          other.code == this.code &&
          other.status == this.status &&
          other.type == this.type &&
          other.priority == this.priority &&
          other.coupon == this.coupon &&
          other.persons == this.persons &&
          other.date == this.date &&
          other.paymentId == this.paymentId &&
          other.tableId == this.tableId &&
          other.source == this.source &&
          other.sourceId == this.sourceId &&
          other.discountPercentage == this.discountPercentage &&
          other.createdBy == this.createdBy &&
          other.takenBy == this.takenBy &&
          other.waiterId == this.waiterId &&
          other.clientId == this.clientId &&
          other.commercialId == this.commercialId &&
          other.note == this.note &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isSynced == this.isSynced);
}

class OrdersCompanion extends UpdateCompanion<Order> {
  final Value<int> id;
  final Value<String> code;
  final Value<String> status;
  final Value<String> type;
  final Value<int> priority;
  final Value<String?> coupon;
  final Value<int> persons;
  final Value<DateTime> date;
  final Value<int?> paymentId;
  final Value<int?> tableId;
  final Value<String?> source;
  final Value<int?> sourceId;
  final Value<double> discountPercentage;
  final Value<int?> createdBy;
  final Value<int?> takenBy;
  final Value<int?> waiterId;
  final Value<int?> clientId;
  final Value<int?> commercialId;
  final Value<String?> note;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isSynced;
  const OrdersCompanion({
    this.id = const Value.absent(),
    this.code = const Value.absent(),
    this.status = const Value.absent(),
    this.type = const Value.absent(),
    this.priority = const Value.absent(),
    this.coupon = const Value.absent(),
    this.persons = const Value.absent(),
    this.date = const Value.absent(),
    this.paymentId = const Value.absent(),
    this.tableId = const Value.absent(),
    this.source = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.discountPercentage = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.takenBy = const Value.absent(),
    this.waiterId = const Value.absent(),
    this.clientId = const Value.absent(),
    this.commercialId = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isSynced = const Value.absent(),
  });
  OrdersCompanion.insert({
    this.id = const Value.absent(),
    required String code,
    this.status = const Value.absent(),
    this.type = const Value.absent(),
    this.priority = const Value.absent(),
    this.coupon = const Value.absent(),
    this.persons = const Value.absent(),
    this.date = const Value.absent(),
    this.paymentId = const Value.absent(),
    this.tableId = const Value.absent(),
    this.source = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.discountPercentage = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.takenBy = const Value.absent(),
    this.waiterId = const Value.absent(),
    this.clientId = const Value.absent(),
    this.commercialId = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isSynced = const Value.absent(),
  }) : code = Value(code);
  static Insertable<Order> custom({
    Expression<int>? id,
    Expression<String>? code,
    Expression<String>? status,
    Expression<String>? type,
    Expression<int>? priority,
    Expression<String>? coupon,
    Expression<int>? persons,
    Expression<DateTime>? date,
    Expression<int>? paymentId,
    Expression<int>? tableId,
    Expression<String>? source,
    Expression<int>? sourceId,
    Expression<double>? discountPercentage,
    Expression<int>? createdBy,
    Expression<int>? takenBy,
    Expression<int>? waiterId,
    Expression<int>? clientId,
    Expression<int>? commercialId,
    Expression<String>? note,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isSynced,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (code != null) 'code': code,
      if (status != null) 'status': status,
      if (type != null) 'type': type,
      if (priority != null) 'priority': priority,
      if (coupon != null) 'coupon': coupon,
      if (persons != null) 'persons': persons,
      if (date != null) 'date': date,
      if (paymentId != null) 'payment_id': paymentId,
      if (tableId != null) 'table_id': tableId,
      if (source != null) 'source': source,
      if (sourceId != null) 'source_id': sourceId,
      if (discountPercentage != null) 'discount_percentage': discountPercentage,
      if (createdBy != null) 'created_by': createdBy,
      if (takenBy != null) 'taken_by': takenBy,
      if (waiterId != null) 'waiter_id': waiterId,
      if (clientId != null) 'client_id': clientId,
      if (commercialId != null) 'commercial_id': commercialId,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isSynced != null) 'is_synced': isSynced,
    });
  }

  OrdersCompanion copyWith({
    Value<int>? id,
    Value<String>? code,
    Value<String>? status,
    Value<String>? type,
    Value<int>? priority,
    Value<String?>? coupon,
    Value<int>? persons,
    Value<DateTime>? date,
    Value<int?>? paymentId,
    Value<int?>? tableId,
    Value<String?>? source,
    Value<int?>? sourceId,
    Value<double>? discountPercentage,
    Value<int?>? createdBy,
    Value<int?>? takenBy,
    Value<int?>? waiterId,
    Value<int?>? clientId,
    Value<int?>? commercialId,
    Value<String?>? note,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? isSynced,
  }) {
    return OrdersCompanion(
      id: id ?? this.id,
      code: code ?? this.code,
      status: status ?? this.status,
      type: type ?? this.type,
      priority: priority ?? this.priority,
      coupon: coupon ?? this.coupon,
      persons: persons ?? this.persons,
      date: date ?? this.date,
      paymentId: paymentId ?? this.paymentId,
      tableId: tableId ?? this.tableId,
      source: source ?? this.source,
      sourceId: sourceId ?? this.sourceId,
      discountPercentage: discountPercentage ?? this.discountPercentage,
      createdBy: createdBy ?? this.createdBy,
      takenBy: takenBy ?? this.takenBy,
      waiterId: waiterId ?? this.waiterId,
      clientId: clientId ?? this.clientId,
      commercialId: commercialId ?? this.commercialId,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (coupon.present) {
      map['coupon'] = Variable<String>(coupon.value);
    }
    if (persons.present) {
      map['persons'] = Variable<int>(persons.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (paymentId.present) {
      map['payment_id'] = Variable<int>(paymentId.value);
    }
    if (tableId.present) {
      map['table_id'] = Variable<int>(tableId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (discountPercentage.present) {
      map['discount_percentage'] = Variable<double>(discountPercentage.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<int>(createdBy.value);
    }
    if (takenBy.present) {
      map['taken_by'] = Variable<int>(takenBy.value);
    }
    if (waiterId.present) {
      map['waiter_id'] = Variable<int>(waiterId.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<int>(clientId.value);
    }
    if (commercialId.present) {
      map['commercial_id'] = Variable<int>(commercialId.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isSynced.present) {
      map['is_synced'] = Variable<bool>(isSynced.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OrdersCompanion(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('status: $status, ')
          ..write('type: $type, ')
          ..write('priority: $priority, ')
          ..write('coupon: $coupon, ')
          ..write('persons: $persons, ')
          ..write('date: $date, ')
          ..write('paymentId: $paymentId, ')
          ..write('tableId: $tableId, ')
          ..write('source: $source, ')
          ..write('sourceId: $sourceId, ')
          ..write('discountPercentage: $discountPercentage, ')
          ..write('createdBy: $createdBy, ')
          ..write('takenBy: $takenBy, ')
          ..write('waiterId: $waiterId, ')
          ..write('clientId: $clientId, ')
          ..write('commercialId: $commercialId, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isSynced: $isSynced')
          ..write(')'))
        .toString();
  }
}

class $OrderProductsTable extends OrderProducts
    with TableInfo<$OrderProductsTable, OrderProduct> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OrderProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _orderIdMeta = const VerificationMeta(
    'orderId',
  );
  @override
  late final GeneratedColumn<int> orderId = GeneratedColumn<int>(
    'order_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<int> productId = GeneratedColumn<int>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _variantIdMeta = const VerificationMeta(
    'variantId',
  );
  @override
  late final GeneratedColumn<int> variantId = GeneratedColumn<int>(
    'variant_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ticketIdMeta = const VerificationMeta(
    'ticketId',
  );
  @override
  late final GeneratedColumn<int> ticketId = GeneratedColumn<int>(
    'ticket_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _unitaryPriceMeta = const VerificationMeta(
    'unitaryPrice',
  );
  @override
  late final GeneratedColumn<double> unitaryPrice = GeneratedColumn<double>(
    'unitary_price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unitaryDiscountMeta = const VerificationMeta(
    'unitaryDiscount',
  );
  @override
  late final GeneratedColumn<double> unitaryDiscount = GeneratedColumn<double>(
    'unitary_discount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _unitaryTvaMeta = const VerificationMeta(
    'unitaryTva',
  );
  @override
  late final GeneratedColumn<double> unitaryTva = GeneratedColumn<double>(
    'unitary_tva',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _manualDiscountMeta = const VerificationMeta(
    'manualDiscount',
  );
  @override
  late final GeneratedColumn<double> manualDiscount = GeneratedColumn<double>(
    'manual_discount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('PENDING'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orderId,
    productId,
    variantId,
    ticketId,
    quantity,
    unitaryPrice,
    unitaryDiscount,
    unitaryTva,
    manualDiscount,
    note,
    state,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'order_products';
  @override
  VerificationContext validateIntegrity(
    Insertable<OrderProduct> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('order_id')) {
      context.handle(
        _orderIdMeta,
        orderId.isAcceptableOrUnknown(data['order_id']!, _orderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orderIdMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('variant_id')) {
      context.handle(
        _variantIdMeta,
        variantId.isAcceptableOrUnknown(data['variant_id']!, _variantIdMeta),
      );
    }
    if (data.containsKey('ticket_id')) {
      context.handle(
        _ticketIdMeta,
        ticketId.isAcceptableOrUnknown(data['ticket_id']!, _ticketIdMeta),
      );
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    }
    if (data.containsKey('unitary_price')) {
      context.handle(
        _unitaryPriceMeta,
        unitaryPrice.isAcceptableOrUnknown(
          data['unitary_price']!,
          _unitaryPriceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_unitaryPriceMeta);
    }
    if (data.containsKey('unitary_discount')) {
      context.handle(
        _unitaryDiscountMeta,
        unitaryDiscount.isAcceptableOrUnknown(
          data['unitary_discount']!,
          _unitaryDiscountMeta,
        ),
      );
    }
    if (data.containsKey('unitary_tva')) {
      context.handle(
        _unitaryTvaMeta,
        unitaryTva.isAcceptableOrUnknown(data['unitary_tva']!, _unitaryTvaMeta),
      );
    }
    if (data.containsKey('manual_discount')) {
      context.handle(
        _manualDiscountMeta,
        manualDiscount.isAcceptableOrUnknown(
          data['manual_discount']!,
          _manualDiscountMeta,
        ),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OrderProduct map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OrderProduct(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      orderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}product_id'],
      )!,
      variantId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}variant_id'],
      ),
      ticketId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ticket_id'],
      ),
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity'],
      )!,
      unitaryPrice: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}unitary_price'],
      )!,
      unitaryDiscount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}unitary_discount'],
      )!,
      unitaryTva: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}unitary_tva'],
      )!,
      manualDiscount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}manual_discount'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $OrderProductsTable createAlias(String alias) {
    return $OrderProductsTable(attachedDatabase, alias);
  }
}

class OrderProduct extends DataClass implements Insertable<OrderProduct> {
  final int id;
  final int orderId;
  final int productId;
  final int? variantId;
  final int? ticketId;
  final int quantity;
  final double unitaryPrice;
  final double unitaryDiscount;
  final double unitaryTva;
  final double manualDiscount;
  final String? note;
  final String state;
  final DateTime updatedAt;
  const OrderProduct({
    required this.id,
    required this.orderId,
    required this.productId,
    this.variantId,
    this.ticketId,
    required this.quantity,
    required this.unitaryPrice,
    required this.unitaryDiscount,
    required this.unitaryTva,
    required this.manualDiscount,
    this.note,
    required this.state,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['order_id'] = Variable<int>(orderId);
    map['product_id'] = Variable<int>(productId);
    if (!nullToAbsent || variantId != null) {
      map['variant_id'] = Variable<int>(variantId);
    }
    if (!nullToAbsent || ticketId != null) {
      map['ticket_id'] = Variable<int>(ticketId);
    }
    map['quantity'] = Variable<int>(quantity);
    map['unitary_price'] = Variable<double>(unitaryPrice);
    map['unitary_discount'] = Variable<double>(unitaryDiscount);
    map['unitary_tva'] = Variable<double>(unitaryTva);
    map['manual_discount'] = Variable<double>(manualDiscount);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['state'] = Variable<String>(state);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  OrderProductsCompanion toCompanion(bool nullToAbsent) {
    return OrderProductsCompanion(
      id: Value(id),
      orderId: Value(orderId),
      productId: Value(productId),
      variantId: variantId == null && nullToAbsent
          ? const Value.absent()
          : Value(variantId),
      ticketId: ticketId == null && nullToAbsent
          ? const Value.absent()
          : Value(ticketId),
      quantity: Value(quantity),
      unitaryPrice: Value(unitaryPrice),
      unitaryDiscount: Value(unitaryDiscount),
      unitaryTva: Value(unitaryTva),
      manualDiscount: Value(manualDiscount),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      state: Value(state),
      updatedAt: Value(updatedAt),
    );
  }

  factory OrderProduct.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OrderProduct(
      id: serializer.fromJson<int>(json['id']),
      orderId: serializer.fromJson<int>(json['orderId']),
      productId: serializer.fromJson<int>(json['productId']),
      variantId: serializer.fromJson<int?>(json['variantId']),
      ticketId: serializer.fromJson<int?>(json['ticketId']),
      quantity: serializer.fromJson<int>(json['quantity']),
      unitaryPrice: serializer.fromJson<double>(json['unitaryPrice']),
      unitaryDiscount: serializer.fromJson<double>(json['unitaryDiscount']),
      unitaryTva: serializer.fromJson<double>(json['unitaryTva']),
      manualDiscount: serializer.fromJson<double>(json['manualDiscount']),
      note: serializer.fromJson<String?>(json['note']),
      state: serializer.fromJson<String>(json['state']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'orderId': serializer.toJson<int>(orderId),
      'productId': serializer.toJson<int>(productId),
      'variantId': serializer.toJson<int?>(variantId),
      'ticketId': serializer.toJson<int?>(ticketId),
      'quantity': serializer.toJson<int>(quantity),
      'unitaryPrice': serializer.toJson<double>(unitaryPrice),
      'unitaryDiscount': serializer.toJson<double>(unitaryDiscount),
      'unitaryTva': serializer.toJson<double>(unitaryTva),
      'manualDiscount': serializer.toJson<double>(manualDiscount),
      'note': serializer.toJson<String?>(note),
      'state': serializer.toJson<String>(state),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  OrderProduct copyWith({
    int? id,
    int? orderId,
    int? productId,
    Value<int?> variantId = const Value.absent(),
    Value<int?> ticketId = const Value.absent(),
    int? quantity,
    double? unitaryPrice,
    double? unitaryDiscount,
    double? unitaryTva,
    double? manualDiscount,
    Value<String?> note = const Value.absent(),
    String? state,
    DateTime? updatedAt,
  }) => OrderProduct(
    id: id ?? this.id,
    orderId: orderId ?? this.orderId,
    productId: productId ?? this.productId,
    variantId: variantId.present ? variantId.value : this.variantId,
    ticketId: ticketId.present ? ticketId.value : this.ticketId,
    quantity: quantity ?? this.quantity,
    unitaryPrice: unitaryPrice ?? this.unitaryPrice,
    unitaryDiscount: unitaryDiscount ?? this.unitaryDiscount,
    unitaryTva: unitaryTva ?? this.unitaryTva,
    manualDiscount: manualDiscount ?? this.manualDiscount,
    note: note.present ? note.value : this.note,
    state: state ?? this.state,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  OrderProduct copyWithCompanion(OrderProductsCompanion data) {
    return OrderProduct(
      id: data.id.present ? data.id.value : this.id,
      orderId: data.orderId.present ? data.orderId.value : this.orderId,
      productId: data.productId.present ? data.productId.value : this.productId,
      variantId: data.variantId.present ? data.variantId.value : this.variantId,
      ticketId: data.ticketId.present ? data.ticketId.value : this.ticketId,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      unitaryPrice: data.unitaryPrice.present
          ? data.unitaryPrice.value
          : this.unitaryPrice,
      unitaryDiscount: data.unitaryDiscount.present
          ? data.unitaryDiscount.value
          : this.unitaryDiscount,
      unitaryTva: data.unitaryTva.present
          ? data.unitaryTva.value
          : this.unitaryTva,
      manualDiscount: data.manualDiscount.present
          ? data.manualDiscount.value
          : this.manualDiscount,
      note: data.note.present ? data.note.value : this.note,
      state: data.state.present ? data.state.value : this.state,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OrderProduct(')
          ..write('id: $id, ')
          ..write('orderId: $orderId, ')
          ..write('productId: $productId, ')
          ..write('variantId: $variantId, ')
          ..write('ticketId: $ticketId, ')
          ..write('quantity: $quantity, ')
          ..write('unitaryPrice: $unitaryPrice, ')
          ..write('unitaryDiscount: $unitaryDiscount, ')
          ..write('unitaryTva: $unitaryTva, ')
          ..write('manualDiscount: $manualDiscount, ')
          ..write('note: $note, ')
          ..write('state: $state, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orderId,
    productId,
    variantId,
    ticketId,
    quantity,
    unitaryPrice,
    unitaryDiscount,
    unitaryTva,
    manualDiscount,
    note,
    state,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OrderProduct &&
          other.id == this.id &&
          other.orderId == this.orderId &&
          other.productId == this.productId &&
          other.variantId == this.variantId &&
          other.ticketId == this.ticketId &&
          other.quantity == this.quantity &&
          other.unitaryPrice == this.unitaryPrice &&
          other.unitaryDiscount == this.unitaryDiscount &&
          other.unitaryTva == this.unitaryTva &&
          other.manualDiscount == this.manualDiscount &&
          other.note == this.note &&
          other.state == this.state &&
          other.updatedAt == this.updatedAt);
}

class OrderProductsCompanion extends UpdateCompanion<OrderProduct> {
  final Value<int> id;
  final Value<int> orderId;
  final Value<int> productId;
  final Value<int?> variantId;
  final Value<int?> ticketId;
  final Value<int> quantity;
  final Value<double> unitaryPrice;
  final Value<double> unitaryDiscount;
  final Value<double> unitaryTva;
  final Value<double> manualDiscount;
  final Value<String?> note;
  final Value<String> state;
  final Value<DateTime> updatedAt;
  const OrderProductsCompanion({
    this.id = const Value.absent(),
    this.orderId = const Value.absent(),
    this.productId = const Value.absent(),
    this.variantId = const Value.absent(),
    this.ticketId = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unitaryPrice = const Value.absent(),
    this.unitaryDiscount = const Value.absent(),
    this.unitaryTva = const Value.absent(),
    this.manualDiscount = const Value.absent(),
    this.note = const Value.absent(),
    this.state = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  OrderProductsCompanion.insert({
    this.id = const Value.absent(),
    required int orderId,
    required int productId,
    this.variantId = const Value.absent(),
    this.ticketId = const Value.absent(),
    this.quantity = const Value.absent(),
    required double unitaryPrice,
    this.unitaryDiscount = const Value.absent(),
    this.unitaryTva = const Value.absent(),
    this.manualDiscount = const Value.absent(),
    this.note = const Value.absent(),
    this.state = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : orderId = Value(orderId),
       productId = Value(productId),
       unitaryPrice = Value(unitaryPrice);
  static Insertable<OrderProduct> custom({
    Expression<int>? id,
    Expression<int>? orderId,
    Expression<int>? productId,
    Expression<int>? variantId,
    Expression<int>? ticketId,
    Expression<int>? quantity,
    Expression<double>? unitaryPrice,
    Expression<double>? unitaryDiscount,
    Expression<double>? unitaryTva,
    Expression<double>? manualDiscount,
    Expression<String>? note,
    Expression<String>? state,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orderId != null) 'order_id': orderId,
      if (productId != null) 'product_id': productId,
      if (variantId != null) 'variant_id': variantId,
      if (ticketId != null) 'ticket_id': ticketId,
      if (quantity != null) 'quantity': quantity,
      if (unitaryPrice != null) 'unitary_price': unitaryPrice,
      if (unitaryDiscount != null) 'unitary_discount': unitaryDiscount,
      if (unitaryTva != null) 'unitary_tva': unitaryTva,
      if (manualDiscount != null) 'manual_discount': manualDiscount,
      if (note != null) 'note': note,
      if (state != null) 'state': state,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  OrderProductsCompanion copyWith({
    Value<int>? id,
    Value<int>? orderId,
    Value<int>? productId,
    Value<int?>? variantId,
    Value<int?>? ticketId,
    Value<int>? quantity,
    Value<double>? unitaryPrice,
    Value<double>? unitaryDiscount,
    Value<double>? unitaryTva,
    Value<double>? manualDiscount,
    Value<String?>? note,
    Value<String>? state,
    Value<DateTime>? updatedAt,
  }) {
    return OrderProductsCompanion(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      productId: productId ?? this.productId,
      variantId: variantId ?? this.variantId,
      ticketId: ticketId ?? this.ticketId,
      quantity: quantity ?? this.quantity,
      unitaryPrice: unitaryPrice ?? this.unitaryPrice,
      unitaryDiscount: unitaryDiscount ?? this.unitaryDiscount,
      unitaryTva: unitaryTva ?? this.unitaryTva,
      manualDiscount: manualDiscount ?? this.manualDiscount,
      note: note ?? this.note,
      state: state ?? this.state,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (orderId.present) {
      map['order_id'] = Variable<int>(orderId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<int>(productId.value);
    }
    if (variantId.present) {
      map['variant_id'] = Variable<int>(variantId.value);
    }
    if (ticketId.present) {
      map['ticket_id'] = Variable<int>(ticketId.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (unitaryPrice.present) {
      map['unitary_price'] = Variable<double>(unitaryPrice.value);
    }
    if (unitaryDiscount.present) {
      map['unitary_discount'] = Variable<double>(unitaryDiscount.value);
    }
    if (unitaryTva.present) {
      map['unitary_tva'] = Variable<double>(unitaryTva.value);
    }
    if (manualDiscount.present) {
      map['manual_discount'] = Variable<double>(manualDiscount.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OrderProductsCompanion(')
          ..write('id: $id, ')
          ..write('orderId: $orderId, ')
          ..write('productId: $productId, ')
          ..write('variantId: $variantId, ')
          ..write('ticketId: $ticketId, ')
          ..write('quantity: $quantity, ')
          ..write('unitaryPrice: $unitaryPrice, ')
          ..write('unitaryDiscount: $unitaryDiscount, ')
          ..write('unitaryTva: $unitaryTva, ')
          ..write('manualDiscount: $manualDiscount, ')
          ..write('note: $note, ')
          ..write('state: $state, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $OrderProductComponentsTable extends OrderProductComponents
    with TableInfo<$OrderProductComponentsTable, OrderProductComponent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OrderProductComponentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _componentIdMeta = const VerificationMeta(
    'componentId',
  );
  @override
  late final GeneratedColumn<int> componentId = GeneratedColumn<int>(
    'component_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orderProductIdMeta = const VerificationMeta(
    'orderProductId',
  );
  @override
  late final GeneratedColumn<int> orderProductId = GeneratedColumn<int>(
    'order_product_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
    'quantity',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
    'price',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _isSpecialMeta = const VerificationMeta(
    'isSpecial',
  );
  @override
  late final GeneratedColumn<bool> isSpecial = GeneratedColumn<bool>(
    'is_special',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_special" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    componentId,
    orderProductId,
    quantity,
    price,
    isSpecial,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'order_product_components';
  @override
  VerificationContext validateIntegrity(
    Insertable<OrderProductComponent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('component_id')) {
      context.handle(
        _componentIdMeta,
        componentId.isAcceptableOrUnknown(
          data['component_id']!,
          _componentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_componentIdMeta);
    }
    if (data.containsKey('order_product_id')) {
      context.handle(
        _orderProductIdMeta,
        orderProductId.isAcceptableOrUnknown(
          data['order_product_id']!,
          _orderProductIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_orderProductIdMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    }
    if (data.containsKey('price')) {
      context.handle(
        _priceMeta,
        price.isAcceptableOrUnknown(data['price']!, _priceMeta),
      );
    }
    if (data.containsKey('is_special')) {
      context.handle(
        _isSpecialMeta,
        isSpecial.isAcceptableOrUnknown(data['is_special']!, _isSpecialMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OrderProductComponent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OrderProductComponent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      componentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}component_id'],
      )!,
      orderProductId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_product_id'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity'],
      )!,
      price: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}price'],
      )!,
      isSpecial: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_special'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $OrderProductComponentsTable createAlias(String alias) {
    return $OrderProductComponentsTable(attachedDatabase, alias);
  }
}

class OrderProductComponent extends DataClass
    implements Insertable<OrderProductComponent> {
  final int id;
  final int componentId;
  final int orderProductId;
  final int quantity;
  final double price;
  final bool isSpecial;
  final DateTime createdAt;
  final DateTime updatedAt;
  const OrderProductComponent({
    required this.id,
    required this.componentId,
    required this.orderProductId,
    required this.quantity,
    required this.price,
    required this.isSpecial,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['component_id'] = Variable<int>(componentId);
    map['order_product_id'] = Variable<int>(orderProductId);
    map['quantity'] = Variable<int>(quantity);
    map['price'] = Variable<double>(price);
    map['is_special'] = Variable<bool>(isSpecial);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  OrderProductComponentsCompanion toCompanion(bool nullToAbsent) {
    return OrderProductComponentsCompanion(
      id: Value(id),
      componentId: Value(componentId),
      orderProductId: Value(orderProductId),
      quantity: Value(quantity),
      price: Value(price),
      isSpecial: Value(isSpecial),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory OrderProductComponent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OrderProductComponent(
      id: serializer.fromJson<int>(json['id']),
      componentId: serializer.fromJson<int>(json['componentId']),
      orderProductId: serializer.fromJson<int>(json['orderProductId']),
      quantity: serializer.fromJson<int>(json['quantity']),
      price: serializer.fromJson<double>(json['price']),
      isSpecial: serializer.fromJson<bool>(json['isSpecial']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'componentId': serializer.toJson<int>(componentId),
      'orderProductId': serializer.toJson<int>(orderProductId),
      'quantity': serializer.toJson<int>(quantity),
      'price': serializer.toJson<double>(price),
      'isSpecial': serializer.toJson<bool>(isSpecial),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  OrderProductComponent copyWith({
    int? id,
    int? componentId,
    int? orderProductId,
    int? quantity,
    double? price,
    bool? isSpecial,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => OrderProductComponent(
    id: id ?? this.id,
    componentId: componentId ?? this.componentId,
    orderProductId: orderProductId ?? this.orderProductId,
    quantity: quantity ?? this.quantity,
    price: price ?? this.price,
    isSpecial: isSpecial ?? this.isSpecial,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  OrderProductComponent copyWithCompanion(
    OrderProductComponentsCompanion data,
  ) {
    return OrderProductComponent(
      id: data.id.present ? data.id.value : this.id,
      componentId: data.componentId.present
          ? data.componentId.value
          : this.componentId,
      orderProductId: data.orderProductId.present
          ? data.orderProductId.value
          : this.orderProductId,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      price: data.price.present ? data.price.value : this.price,
      isSpecial: data.isSpecial.present ? data.isSpecial.value : this.isSpecial,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OrderProductComponent(')
          ..write('id: $id, ')
          ..write('componentId: $componentId, ')
          ..write('orderProductId: $orderProductId, ')
          ..write('quantity: $quantity, ')
          ..write('price: $price, ')
          ..write('isSpecial: $isSpecial, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    componentId,
    orderProductId,
    quantity,
    price,
    isSpecial,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OrderProductComponent &&
          other.id == this.id &&
          other.componentId == this.componentId &&
          other.orderProductId == this.orderProductId &&
          other.quantity == this.quantity &&
          other.price == this.price &&
          other.isSpecial == this.isSpecial &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class OrderProductComponentsCompanion
    extends UpdateCompanion<OrderProductComponent> {
  final Value<int> id;
  final Value<int> componentId;
  final Value<int> orderProductId;
  final Value<int> quantity;
  final Value<double> price;
  final Value<bool> isSpecial;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const OrderProductComponentsCompanion({
    this.id = const Value.absent(),
    this.componentId = const Value.absent(),
    this.orderProductId = const Value.absent(),
    this.quantity = const Value.absent(),
    this.price = const Value.absent(),
    this.isSpecial = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  OrderProductComponentsCompanion.insert({
    this.id = const Value.absent(),
    required int componentId,
    required int orderProductId,
    this.quantity = const Value.absent(),
    this.price = const Value.absent(),
    this.isSpecial = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : componentId = Value(componentId),
       orderProductId = Value(orderProductId);
  static Insertable<OrderProductComponent> custom({
    Expression<int>? id,
    Expression<int>? componentId,
    Expression<int>? orderProductId,
    Expression<int>? quantity,
    Expression<double>? price,
    Expression<bool>? isSpecial,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (componentId != null) 'component_id': componentId,
      if (orderProductId != null) 'order_product_id': orderProductId,
      if (quantity != null) 'quantity': quantity,
      if (price != null) 'price': price,
      if (isSpecial != null) 'is_special': isSpecial,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  OrderProductComponentsCompanion copyWith({
    Value<int>? id,
    Value<int>? componentId,
    Value<int>? orderProductId,
    Value<int>? quantity,
    Value<double>? price,
    Value<bool>? isSpecial,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return OrderProductComponentsCompanion(
      id: id ?? this.id,
      componentId: componentId ?? this.componentId,
      orderProductId: orderProductId ?? this.orderProductId,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      isSpecial: isSpecial ?? this.isSpecial,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (componentId.present) {
      map['component_id'] = Variable<int>(componentId.value);
    }
    if (orderProductId.present) {
      map['order_product_id'] = Variable<int>(orderProductId.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (isSpecial.present) {
      map['is_special'] = Variable<bool>(isSpecial.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OrderProductComponentsCompanion(')
          ..write('id: $id, ')
          ..write('componentId: $componentId, ')
          ..write('orderProductId: $orderProductId, ')
          ..write('quantity: $quantity, ')
          ..write('price: $price, ')
          ..write('isSpecial: $isSpecial, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $PaymentsTable extends Payments with TableInfo<$PaymentsTable, Payment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metaDataMeta = const VerificationMeta(
    'metaData',
  );
  @override
  late final GeneratedColumn<String> metaData = GeneratedColumn<String>(
    'meta_data',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    date,
    code,
    amount,
    metaData,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'payments';
  @override
  VerificationContext validateIntegrity(
    Insertable<Payment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('meta_data')) {
      context.handle(
        _metaDataMeta,
        metaData.isAcceptableOrUnknown(data['meta_data']!, _metaDataMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Payment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Payment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount'],
      )!,
      metaData: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meta_data'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PaymentsTable createAlias(String alias) {
    return $PaymentsTable(attachedDatabase, alias);
  }
}

class Payment extends DataClass implements Insertable<Payment> {
  final int id;
  final DateTime date;
  final String code;
  final double amount;
  final String? metaData;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Payment({
    required this.id,
    required this.date,
    required this.code,
    required this.amount,
    this.metaData,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['date'] = Variable<DateTime>(date);
    map['code'] = Variable<String>(code);
    map['amount'] = Variable<double>(amount);
    if (!nullToAbsent || metaData != null) {
      map['meta_data'] = Variable<String>(metaData);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PaymentsCompanion toCompanion(bool nullToAbsent) {
    return PaymentsCompanion(
      id: Value(id),
      date: Value(date),
      code: Value(code),
      amount: Value(amount),
      metaData: metaData == null && nullToAbsent
          ? const Value.absent()
          : Value(metaData),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Payment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Payment(
      id: serializer.fromJson<int>(json['id']),
      date: serializer.fromJson<DateTime>(json['date']),
      code: serializer.fromJson<String>(json['code']),
      amount: serializer.fromJson<double>(json['amount']),
      metaData: serializer.fromJson<String?>(json['metaData']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'date': serializer.toJson<DateTime>(date),
      'code': serializer.toJson<String>(code),
      'amount': serializer.toJson<double>(amount),
      'metaData': serializer.toJson<String?>(metaData),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Payment copyWith({
    int? id,
    DateTime? date,
    String? code,
    double? amount,
    Value<String?> metaData = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Payment(
    id: id ?? this.id,
    date: date ?? this.date,
    code: code ?? this.code,
    amount: amount ?? this.amount,
    metaData: metaData.present ? metaData.value : this.metaData,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Payment copyWithCompanion(PaymentsCompanion data) {
    return Payment(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      code: data.code.present ? data.code.value : this.code,
      amount: data.amount.present ? data.amount.value : this.amount,
      metaData: data.metaData.present ? data.metaData.value : this.metaData,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Payment(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('code: $code, ')
          ..write('amount: $amount, ')
          ..write('metaData: $metaData, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, date, code, amount, metaData, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Payment &&
          other.id == this.id &&
          other.date == this.date &&
          other.code == this.code &&
          other.amount == this.amount &&
          other.metaData == this.metaData &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PaymentsCompanion extends UpdateCompanion<Payment> {
  final Value<int> id;
  final Value<DateTime> date;
  final Value<String> code;
  final Value<double> amount;
  final Value<String?> metaData;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const PaymentsCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.code = const Value.absent(),
    this.amount = const Value.absent(),
    this.metaData = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  PaymentsCompanion.insert({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    required String code,
    required double amount,
    this.metaData = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : code = Value(code),
       amount = Value(amount);
  static Insertable<Payment> custom({
    Expression<int>? id,
    Expression<DateTime>? date,
    Expression<String>? code,
    Expression<double>? amount,
    Expression<String>? metaData,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (code != null) 'code': code,
      if (amount != null) 'amount': amount,
      if (metaData != null) 'meta_data': metaData,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  PaymentsCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? date,
    Value<String>? code,
    Value<double>? amount,
    Value<String?>? metaData,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return PaymentsCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      code: code ?? this.code,
      amount: amount ?? this.amount,
      metaData: metaData ?? this.metaData,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (metaData.present) {
      map['meta_data'] = Variable<String>(metaData.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PaymentsCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('code: $code, ')
          ..write('amount: $amount, ')
          ..write('metaData: $metaData, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $TransactionsTable extends Transactions
    with TableInfo<$TransactionsTable, Transaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _paymentIdMeta = const VerificationMeta(
    'paymentId',
  );
  @override
  late final GeneratedColumn<int> paymentId = GeneratedColumn<int>(
    'payment_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _referenceIdMeta = const VerificationMeta(
    'referenceId',
  );
  @override
  late final GeneratedColumn<String> referenceId = GeneratedColumn<String>(
    'reference_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metaDataMeta = const VerificationMeta(
    'metaData',
  );
  @override
  late final GeneratedColumn<String> metaData = GeneratedColumn<String>(
    'meta_data',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    paymentId,
    referenceId,
    amount,
    date,
    type,
    metaData,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Transaction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('payment_id')) {
      context.handle(
        _paymentIdMeta,
        paymentId.isAcceptableOrUnknown(data['payment_id']!, _paymentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_paymentIdMeta);
    }
    if (data.containsKey('reference_id')) {
      context.handle(
        _referenceIdMeta,
        referenceId.isAcceptableOrUnknown(
          data['reference_id']!,
          _referenceIdMeta,
        ),
      );
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('meta_data')) {
      context.handle(
        _metaDataMeta,
        metaData.isAcceptableOrUnknown(data['meta_data']!, _metaDataMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Transaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Transaction(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      paymentId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payment_id'],
      )!,
      referenceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference_id'],
      ),
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      metaData: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}meta_data'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TransactionsTable createAlias(String alias) {
    return $TransactionsTable(attachedDatabase, alias);
  }
}

class Transaction extends DataClass implements Insertable<Transaction> {
  final int id;
  final int paymentId;
  final String? referenceId;
  final double amount;
  final DateTime date;
  final String type;
  final String? metaData;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Transaction({
    required this.id,
    required this.paymentId,
    this.referenceId,
    required this.amount,
    required this.date,
    required this.type,
    this.metaData,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['payment_id'] = Variable<int>(paymentId);
    if (!nullToAbsent || referenceId != null) {
      map['reference_id'] = Variable<String>(referenceId);
    }
    map['amount'] = Variable<double>(amount);
    map['date'] = Variable<DateTime>(date);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || metaData != null) {
      map['meta_data'] = Variable<String>(metaData);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TransactionsCompanion toCompanion(bool nullToAbsent) {
    return TransactionsCompanion(
      id: Value(id),
      paymentId: Value(paymentId),
      referenceId: referenceId == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceId),
      amount: Value(amount),
      date: Value(date),
      type: Value(type),
      metaData: metaData == null && nullToAbsent
          ? const Value.absent()
          : Value(metaData),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Transaction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Transaction(
      id: serializer.fromJson<int>(json['id']),
      paymentId: serializer.fromJson<int>(json['paymentId']),
      referenceId: serializer.fromJson<String?>(json['referenceId']),
      amount: serializer.fromJson<double>(json['amount']),
      date: serializer.fromJson<DateTime>(json['date']),
      type: serializer.fromJson<String>(json['type']),
      metaData: serializer.fromJson<String?>(json['metaData']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'paymentId': serializer.toJson<int>(paymentId),
      'referenceId': serializer.toJson<String?>(referenceId),
      'amount': serializer.toJson<double>(amount),
      'date': serializer.toJson<DateTime>(date),
      'type': serializer.toJson<String>(type),
      'metaData': serializer.toJson<String?>(metaData),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Transaction copyWith({
    int? id,
    int? paymentId,
    Value<String?> referenceId = const Value.absent(),
    double? amount,
    DateTime? date,
    String? type,
    Value<String?> metaData = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Transaction(
    id: id ?? this.id,
    paymentId: paymentId ?? this.paymentId,
    referenceId: referenceId.present ? referenceId.value : this.referenceId,
    amount: amount ?? this.amount,
    date: date ?? this.date,
    type: type ?? this.type,
    metaData: metaData.present ? metaData.value : this.metaData,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Transaction copyWithCompanion(TransactionsCompanion data) {
    return Transaction(
      id: data.id.present ? data.id.value : this.id,
      paymentId: data.paymentId.present ? data.paymentId.value : this.paymentId,
      referenceId: data.referenceId.present
          ? data.referenceId.value
          : this.referenceId,
      amount: data.amount.present ? data.amount.value : this.amount,
      date: data.date.present ? data.date.value : this.date,
      type: data.type.present ? data.type.value : this.type,
      metaData: data.metaData.present ? data.metaData.value : this.metaData,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Transaction(')
          ..write('id: $id, ')
          ..write('paymentId: $paymentId, ')
          ..write('referenceId: $referenceId, ')
          ..write('amount: $amount, ')
          ..write('date: $date, ')
          ..write('type: $type, ')
          ..write('metaData: $metaData, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    paymentId,
    referenceId,
    amount,
    date,
    type,
    metaData,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Transaction &&
          other.id == this.id &&
          other.paymentId == this.paymentId &&
          other.referenceId == this.referenceId &&
          other.amount == this.amount &&
          other.date == this.date &&
          other.type == this.type &&
          other.metaData == this.metaData &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class TransactionsCompanion extends UpdateCompanion<Transaction> {
  final Value<int> id;
  final Value<int> paymentId;
  final Value<String?> referenceId;
  final Value<double> amount;
  final Value<DateTime> date;
  final Value<String> type;
  final Value<String?> metaData;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const TransactionsCompanion({
    this.id = const Value.absent(),
    this.paymentId = const Value.absent(),
    this.referenceId = const Value.absent(),
    this.amount = const Value.absent(),
    this.date = const Value.absent(),
    this.type = const Value.absent(),
    this.metaData = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  TransactionsCompanion.insert({
    this.id = const Value.absent(),
    required int paymentId,
    this.referenceId = const Value.absent(),
    required double amount,
    this.date = const Value.absent(),
    required String type,
    this.metaData = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : paymentId = Value(paymentId),
       amount = Value(amount),
       type = Value(type);
  static Insertable<Transaction> custom({
    Expression<int>? id,
    Expression<int>? paymentId,
    Expression<String>? referenceId,
    Expression<double>? amount,
    Expression<DateTime>? date,
    Expression<String>? type,
    Expression<String>? metaData,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (paymentId != null) 'payment_id': paymentId,
      if (referenceId != null) 'reference_id': referenceId,
      if (amount != null) 'amount': amount,
      if (date != null) 'date': date,
      if (type != null) 'type': type,
      if (metaData != null) 'meta_data': metaData,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  TransactionsCompanion copyWith({
    Value<int>? id,
    Value<int>? paymentId,
    Value<String?>? referenceId,
    Value<double>? amount,
    Value<DateTime>? date,
    Value<String>? type,
    Value<String?>? metaData,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return TransactionsCompanion(
      id: id ?? this.id,
      paymentId: paymentId ?? this.paymentId,
      referenceId: referenceId ?? this.referenceId,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      type: type ?? this.type,
      metaData: metaData ?? this.metaData,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (paymentId.present) {
      map['payment_id'] = Variable<int>(paymentId.value);
    }
    if (referenceId.present) {
      map['reference_id'] = Variable<String>(referenceId.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (metaData.present) {
      map['meta_data'] = Variable<String>(metaData.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionsCompanion(')
          ..write('id: $id, ')
          ..write('paymentId: $paymentId, ')
          ..write('referenceId: $referenceId, ')
          ..write('amount: $amount, ')
          ..write('date: $date, ')
          ..write('type: $type, ')
          ..write('metaData: $metaData, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $CashSessionsTable extends CashSessions
    with TableInfo<$CashSessionsTable, CashSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CashSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _cashierIdMeta = const VerificationMeta(
    'cashierId',
  );
  @override
  late final GeneratedColumn<int> cashierId = GeneratedColumn<int>(
    'cashier_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pausedAtMeta = const VerificationMeta(
    'pausedAt',
  );
  @override
  late final GeneratedColumn<DateTime> pausedAt = GeneratedColumn<DateTime>(
    'paused_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _moneyAtStartMeta = const VerificationMeta(
    'moneyAtStart',
  );
  @override
  late final GeneratedColumn<double> moneyAtStart = GeneratedColumn<double>(
    'money_at_start',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _moneyAtEndMeta = const VerificationMeta(
    'moneyAtEnd',
  );
  @override
  late final GeneratedColumn<double> moneyAtEnd = GeneratedColumn<double>(
    'money_at_end',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _isSyncedMeta = const VerificationMeta(
    'isSynced',
  );
  @override
  late final GeneratedColumn<bool> isSynced = GeneratedColumn<bool>(
    'is_synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    code,
    cashierId,
    startedAt,
    endedAt,
    pausedAt,
    moneyAtStart,
    moneyAtEnd,
    status,
    isSynced,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cash_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<CashSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('cashier_id')) {
      context.handle(
        _cashierIdMeta,
        cashierId.isAcceptableOrUnknown(data['cashier_id']!, _cashierIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cashierIdMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('paused_at')) {
      context.handle(
        _pausedAtMeta,
        pausedAt.isAcceptableOrUnknown(data['paused_at']!, _pausedAtMeta),
      );
    }
    if (data.containsKey('money_at_start')) {
      context.handle(
        _moneyAtStartMeta,
        moneyAtStart.isAcceptableOrUnknown(
          data['money_at_start']!,
          _moneyAtStartMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_moneyAtStartMeta);
    }
    if (data.containsKey('money_at_end')) {
      context.handle(
        _moneyAtEndMeta,
        moneyAtEnd.isAcceptableOrUnknown(
          data['money_at_end']!,
          _moneyAtEndMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('is_synced')) {
      context.handle(
        _isSyncedMeta,
        isSynced.isAcceptableOrUnknown(data['is_synced']!, _isSyncedMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CashSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CashSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      cashierId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cashier_id'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ended_at'],
      ),
      pausedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}paused_at'],
      ),
      moneyAtStart: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}money_at_start'],
      )!,
      moneyAtEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}money_at_end'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      isSynced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_synced'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CashSessionsTable createAlias(String alias) {
    return $CashSessionsTable(attachedDatabase, alias);
  }
}

class CashSession extends DataClass implements Insertable<CashSession> {
  final int id;
  final String code;
  final int cashierId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime? pausedAt;
  final double moneyAtStart;
  final double? moneyAtEnd;
  final String status;
  final bool isSynced;
  final DateTime updatedAt;
  const CashSession({
    required this.id,
    required this.code,
    required this.cashierId,
    required this.startedAt,
    this.endedAt,
    this.pausedAt,
    required this.moneyAtStart,
    this.moneyAtEnd,
    required this.status,
    required this.isSynced,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['code'] = Variable<String>(code);
    map['cashier_id'] = Variable<int>(cashierId);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    if (!nullToAbsent || pausedAt != null) {
      map['paused_at'] = Variable<DateTime>(pausedAt);
    }
    map['money_at_start'] = Variable<double>(moneyAtStart);
    if (!nullToAbsent || moneyAtEnd != null) {
      map['money_at_end'] = Variable<double>(moneyAtEnd);
    }
    map['status'] = Variable<String>(status);
    map['is_synced'] = Variable<bool>(isSynced);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CashSessionsCompanion toCompanion(bool nullToAbsent) {
    return CashSessionsCompanion(
      id: Value(id),
      code: Value(code),
      cashierId: Value(cashierId),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      pausedAt: pausedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(pausedAt),
      moneyAtStart: Value(moneyAtStart),
      moneyAtEnd: moneyAtEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(moneyAtEnd),
      status: Value(status),
      isSynced: Value(isSynced),
      updatedAt: Value(updatedAt),
    );
  }

  factory CashSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CashSession(
      id: serializer.fromJson<int>(json['id']),
      code: serializer.fromJson<String>(json['code']),
      cashierId: serializer.fromJson<int>(json['cashierId']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
      pausedAt: serializer.fromJson<DateTime?>(json['pausedAt']),
      moneyAtStart: serializer.fromJson<double>(json['moneyAtStart']),
      moneyAtEnd: serializer.fromJson<double?>(json['moneyAtEnd']),
      status: serializer.fromJson<String>(json['status']),
      isSynced: serializer.fromJson<bool>(json['isSynced']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'code': serializer.toJson<String>(code),
      'cashierId': serializer.toJson<int>(cashierId),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
      'pausedAt': serializer.toJson<DateTime?>(pausedAt),
      'moneyAtStart': serializer.toJson<double>(moneyAtStart),
      'moneyAtEnd': serializer.toJson<double?>(moneyAtEnd),
      'status': serializer.toJson<String>(status),
      'isSynced': serializer.toJson<bool>(isSynced),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CashSession copyWith({
    int? id,
    String? code,
    int? cashierId,
    DateTime? startedAt,
    Value<DateTime?> endedAt = const Value.absent(),
    Value<DateTime?> pausedAt = const Value.absent(),
    double? moneyAtStart,
    Value<double?> moneyAtEnd = const Value.absent(),
    String? status,
    bool? isSynced,
    DateTime? updatedAt,
  }) => CashSession(
    id: id ?? this.id,
    code: code ?? this.code,
    cashierId: cashierId ?? this.cashierId,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    pausedAt: pausedAt.present ? pausedAt.value : this.pausedAt,
    moneyAtStart: moneyAtStart ?? this.moneyAtStart,
    moneyAtEnd: moneyAtEnd.present ? moneyAtEnd.value : this.moneyAtEnd,
    status: status ?? this.status,
    isSynced: isSynced ?? this.isSynced,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CashSession copyWithCompanion(CashSessionsCompanion data) {
    return CashSession(
      id: data.id.present ? data.id.value : this.id,
      code: data.code.present ? data.code.value : this.code,
      cashierId: data.cashierId.present ? data.cashierId.value : this.cashierId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      pausedAt: data.pausedAt.present ? data.pausedAt.value : this.pausedAt,
      moneyAtStart: data.moneyAtStart.present
          ? data.moneyAtStart.value
          : this.moneyAtStart,
      moneyAtEnd: data.moneyAtEnd.present
          ? data.moneyAtEnd.value
          : this.moneyAtEnd,
      status: data.status.present ? data.status.value : this.status,
      isSynced: data.isSynced.present ? data.isSynced.value : this.isSynced,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CashSession(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('cashierId: $cashierId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('pausedAt: $pausedAt, ')
          ..write('moneyAtStart: $moneyAtStart, ')
          ..write('moneyAtEnd: $moneyAtEnd, ')
          ..write('status: $status, ')
          ..write('isSynced: $isSynced, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    code,
    cashierId,
    startedAt,
    endedAt,
    pausedAt,
    moneyAtStart,
    moneyAtEnd,
    status,
    isSynced,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CashSession &&
          other.id == this.id &&
          other.code == this.code &&
          other.cashierId == this.cashierId &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.pausedAt == this.pausedAt &&
          other.moneyAtStart == this.moneyAtStart &&
          other.moneyAtEnd == this.moneyAtEnd &&
          other.status == this.status &&
          other.isSynced == this.isSynced &&
          other.updatedAt == this.updatedAt);
}

class CashSessionsCompanion extends UpdateCompanion<CashSession> {
  final Value<int> id;
  final Value<String> code;
  final Value<int> cashierId;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<DateTime?> pausedAt;
  final Value<double> moneyAtStart;
  final Value<double?> moneyAtEnd;
  final Value<String> status;
  final Value<bool> isSynced;
  final Value<DateTime> updatedAt;
  const CashSessionsCompanion({
    this.id = const Value.absent(),
    this.code = const Value.absent(),
    this.cashierId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.pausedAt = const Value.absent(),
    this.moneyAtStart = const Value.absent(),
    this.moneyAtEnd = const Value.absent(),
    this.status = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  CashSessionsCompanion.insert({
    this.id = const Value.absent(),
    required String code,
    required int cashierId,
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.pausedAt = const Value.absent(),
    required double moneyAtStart,
    this.moneyAtEnd = const Value.absent(),
    this.status = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : code = Value(code),
       cashierId = Value(cashierId),
       moneyAtStart = Value(moneyAtStart);
  static Insertable<CashSession> custom({
    Expression<int>? id,
    Expression<String>? code,
    Expression<int>? cashierId,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<DateTime>? pausedAt,
    Expression<double>? moneyAtStart,
    Expression<double>? moneyAtEnd,
    Expression<String>? status,
    Expression<bool>? isSynced,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (code != null) 'code': code,
      if (cashierId != null) 'cashier_id': cashierId,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (pausedAt != null) 'paused_at': pausedAt,
      if (moneyAtStart != null) 'money_at_start': moneyAtStart,
      if (moneyAtEnd != null) 'money_at_end': moneyAtEnd,
      if (status != null) 'status': status,
      if (isSynced != null) 'is_synced': isSynced,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  CashSessionsCompanion copyWith({
    Value<int>? id,
    Value<String>? code,
    Value<int>? cashierId,
    Value<DateTime>? startedAt,
    Value<DateTime?>? endedAt,
    Value<DateTime?>? pausedAt,
    Value<double>? moneyAtStart,
    Value<double?>? moneyAtEnd,
    Value<String>? status,
    Value<bool>? isSynced,
    Value<DateTime>? updatedAt,
  }) {
    return CashSessionsCompanion(
      id: id ?? this.id,
      code: code ?? this.code,
      cashierId: cashierId ?? this.cashierId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      pausedAt: pausedAt ?? this.pausedAt,
      moneyAtStart: moneyAtStart ?? this.moneyAtStart,
      moneyAtEnd: moneyAtEnd ?? this.moneyAtEnd,
      status: status ?? this.status,
      isSynced: isSynced ?? this.isSynced,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (cashierId.present) {
      map['cashier_id'] = Variable<int>(cashierId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (pausedAt.present) {
      map['paused_at'] = Variable<DateTime>(pausedAt.value);
    }
    if (moneyAtStart.present) {
      map['money_at_start'] = Variable<double>(moneyAtStart.value);
    }
    if (moneyAtEnd.present) {
      map['money_at_end'] = Variable<double>(moneyAtEnd.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (isSynced.present) {
      map['is_synced'] = Variable<bool>(isSynced.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CashSessionsCompanion(')
          ..write('id: $id, ')
          ..write('code: $code, ')
          ..write('cashierId: $cashierId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('pausedAt: $pausedAt, ')
          ..write('moneyAtStart: $moneyAtStart, ')
          ..write('moneyAtEnd: $moneyAtEnd, ')
          ..write('status: $status, ')
          ..write('isSynced: $isSynced, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $TicketsTable extends Tickets with TableInfo<$TicketsTable, Ticket> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TicketsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _numMeta = const VerificationMeta('num');
  @override
  late final GeneratedColumn<String> num = GeneratedColumn<String>(
    'num',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _orderIdMeta = const VerificationMeta(
    'orderId',
  );
  @override
  late final GeneratedColumn<int> orderId = GeneratedColumn<int>(
    'order_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES orders (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _printCountMeta = const VerificationMeta(
    'printCount',
  );
  @override
  late final GeneratedColumn<int> printCount = GeneratedColumn<int>(
    'print_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _paymentMethodMeta = const VerificationMeta(
    'paymentMethod',
  );
  @override
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
    'payment_method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isPaidMeta = const VerificationMeta('isPaid');
  @override
  late final GeneratedColumn<bool> isPaid = GeneratedColumn<bool>(
    'is_paid',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_paid" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isSyncedMeta = const VerificationMeta(
    'isSynced',
  );
  @override
  late final GeneratedColumn<bool> isSynced = GeneratedColumn<bool>(
    'is_synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    num,
    date,
    orderId,
    sessionId,
    printCount,
    paymentMethod,
    amount,
    isPaid,
    isSynced,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tickets';
  @override
  VerificationContext validateIntegrity(
    Insertable<Ticket> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('num')) {
      context.handle(
        _numMeta,
        num.isAcceptableOrUnknown(data['num']!, _numMeta),
      );
    } else if (isInserting) {
      context.missing(_numMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    }
    if (data.containsKey('order_id')) {
      context.handle(
        _orderIdMeta,
        orderId.isAcceptableOrUnknown(data['order_id']!, _orderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orderIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('print_count')) {
      context.handle(
        _printCountMeta,
        printCount.isAcceptableOrUnknown(data['print_count']!, _printCountMeta),
      );
    }
    if (data.containsKey('payment_method')) {
      context.handle(
        _paymentMethodMeta,
        paymentMethod.isAcceptableOrUnknown(
          data['payment_method']!,
          _paymentMethodMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_paymentMethodMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('is_paid')) {
      context.handle(
        _isPaidMeta,
        isPaid.isAcceptableOrUnknown(data['is_paid']!, _isPaidMeta),
      );
    }
    if (data.containsKey('is_synced')) {
      context.handle(
        _isSyncedMeta,
        isSynced.isAcceptableOrUnknown(data['is_synced']!, _isSyncedMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Ticket map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Ticket(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      num: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}num'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      orderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      ),
      printCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}print_count'],
      )!,
      paymentMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_method'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount'],
      )!,
      isPaid: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_paid'],
      )!,
      isSynced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_synced'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $TicketsTable createAlias(String alias) {
    return $TicketsTable(attachedDatabase, alias);
  }
}

class Ticket extends DataClass implements Insertable<Ticket> {
  final int id;
  final String num;
  final DateTime date;
  final int orderId;
  final int? sessionId;
  final int printCount;
  final String paymentMethod;
  final double amount;
  final bool isPaid;
  final bool isSynced;
  final DateTime updatedAt;
  const Ticket({
    required this.id,
    required this.num,
    required this.date,
    required this.orderId,
    this.sessionId,
    required this.printCount,
    required this.paymentMethod,
    required this.amount,
    required this.isPaid,
    required this.isSynced,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['num'] = Variable<String>(num);
    map['date'] = Variable<DateTime>(date);
    map['order_id'] = Variable<int>(orderId);
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<int>(sessionId);
    }
    map['print_count'] = Variable<int>(printCount);
    map['payment_method'] = Variable<String>(paymentMethod);
    map['amount'] = Variable<double>(amount);
    map['is_paid'] = Variable<bool>(isPaid);
    map['is_synced'] = Variable<bool>(isSynced);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  TicketsCompanion toCompanion(bool nullToAbsent) {
    return TicketsCompanion(
      id: Value(id),
      num: Value(num),
      date: Value(date),
      orderId: Value(orderId),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      printCount: Value(printCount),
      paymentMethod: Value(paymentMethod),
      amount: Value(amount),
      isPaid: Value(isPaid),
      isSynced: Value(isSynced),
      updatedAt: Value(updatedAt),
    );
  }

  factory Ticket.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Ticket(
      id: serializer.fromJson<int>(json['id']),
      num: serializer.fromJson<String>(json['num']),
      date: serializer.fromJson<DateTime>(json['date']),
      orderId: serializer.fromJson<int>(json['orderId']),
      sessionId: serializer.fromJson<int?>(json['sessionId']),
      printCount: serializer.fromJson<int>(json['printCount']),
      paymentMethod: serializer.fromJson<String>(json['paymentMethod']),
      amount: serializer.fromJson<double>(json['amount']),
      isPaid: serializer.fromJson<bool>(json['isPaid']),
      isSynced: serializer.fromJson<bool>(json['isSynced']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'num': serializer.toJson<String>(num),
      'date': serializer.toJson<DateTime>(date),
      'orderId': serializer.toJson<int>(orderId),
      'sessionId': serializer.toJson<int?>(sessionId),
      'printCount': serializer.toJson<int>(printCount),
      'paymentMethod': serializer.toJson<String>(paymentMethod),
      'amount': serializer.toJson<double>(amount),
      'isPaid': serializer.toJson<bool>(isPaid),
      'isSynced': serializer.toJson<bool>(isSynced),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Ticket copyWith({
    int? id,
    String? num,
    DateTime? date,
    int? orderId,
    Value<int?> sessionId = const Value.absent(),
    int? printCount,
    String? paymentMethod,
    double? amount,
    bool? isPaid,
    bool? isSynced,
    DateTime? updatedAt,
  }) => Ticket(
    id: id ?? this.id,
    num: num ?? this.num,
    date: date ?? this.date,
    orderId: orderId ?? this.orderId,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    printCount: printCount ?? this.printCount,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    amount: amount ?? this.amount,
    isPaid: isPaid ?? this.isPaid,
    isSynced: isSynced ?? this.isSynced,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Ticket copyWithCompanion(TicketsCompanion data) {
    return Ticket(
      id: data.id.present ? data.id.value : this.id,
      num: data.num.present ? data.num.value : this.num,
      date: data.date.present ? data.date.value : this.date,
      orderId: data.orderId.present ? data.orderId.value : this.orderId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      printCount: data.printCount.present
          ? data.printCount.value
          : this.printCount,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      amount: data.amount.present ? data.amount.value : this.amount,
      isPaid: data.isPaid.present ? data.isPaid.value : this.isPaid,
      isSynced: data.isSynced.present ? data.isSynced.value : this.isSynced,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Ticket(')
          ..write('id: $id, ')
          ..write('num: $num, ')
          ..write('date: $date, ')
          ..write('orderId: $orderId, ')
          ..write('sessionId: $sessionId, ')
          ..write('printCount: $printCount, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('amount: $amount, ')
          ..write('isPaid: $isPaid, ')
          ..write('isSynced: $isSynced, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    num,
    date,
    orderId,
    sessionId,
    printCount,
    paymentMethod,
    amount,
    isPaid,
    isSynced,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Ticket &&
          other.id == this.id &&
          other.num == this.num &&
          other.date == this.date &&
          other.orderId == this.orderId &&
          other.sessionId == this.sessionId &&
          other.printCount == this.printCount &&
          other.paymentMethod == this.paymentMethod &&
          other.amount == this.amount &&
          other.isPaid == this.isPaid &&
          other.isSynced == this.isSynced &&
          other.updatedAt == this.updatedAt);
}

class TicketsCompanion extends UpdateCompanion<Ticket> {
  final Value<int> id;
  final Value<String> num;
  final Value<DateTime> date;
  final Value<int> orderId;
  final Value<int?> sessionId;
  final Value<int> printCount;
  final Value<String> paymentMethod;
  final Value<double> amount;
  final Value<bool> isPaid;
  final Value<bool> isSynced;
  final Value<DateTime> updatedAt;
  const TicketsCompanion({
    this.id = const Value.absent(),
    this.num = const Value.absent(),
    this.date = const Value.absent(),
    this.orderId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.printCount = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.amount = const Value.absent(),
    this.isPaid = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  TicketsCompanion.insert({
    this.id = const Value.absent(),
    required String num,
    this.date = const Value.absent(),
    required int orderId,
    this.sessionId = const Value.absent(),
    this.printCount = const Value.absent(),
    required String paymentMethod,
    required double amount,
    this.isPaid = const Value.absent(),
    this.isSynced = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : num = Value(num),
       orderId = Value(orderId),
       paymentMethod = Value(paymentMethod),
       amount = Value(amount);
  static Insertable<Ticket> custom({
    Expression<int>? id,
    Expression<String>? num,
    Expression<DateTime>? date,
    Expression<int>? orderId,
    Expression<int>? sessionId,
    Expression<int>? printCount,
    Expression<String>? paymentMethod,
    Expression<double>? amount,
    Expression<bool>? isPaid,
    Expression<bool>? isSynced,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (num != null) 'num': num,
      if (date != null) 'date': date,
      if (orderId != null) 'order_id': orderId,
      if (sessionId != null) 'session_id': sessionId,
      if (printCount != null) 'print_count': printCount,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (amount != null) 'amount': amount,
      if (isPaid != null) 'is_paid': isPaid,
      if (isSynced != null) 'is_synced': isSynced,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  TicketsCompanion copyWith({
    Value<int>? id,
    Value<String>? num,
    Value<DateTime>? date,
    Value<int>? orderId,
    Value<int?>? sessionId,
    Value<int>? printCount,
    Value<String>? paymentMethod,
    Value<double>? amount,
    Value<bool>? isPaid,
    Value<bool>? isSynced,
    Value<DateTime>? updatedAt,
  }) {
    return TicketsCompanion(
      id: id ?? this.id,
      num: num ?? this.num,
      date: date ?? this.date,
      orderId: orderId ?? this.orderId,
      sessionId: sessionId ?? this.sessionId,
      printCount: printCount ?? this.printCount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      amount: amount ?? this.amount,
      isPaid: isPaid ?? this.isPaid,
      isSynced: isSynced ?? this.isSynced,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (num.present) {
      map['num'] = Variable<String>(num.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (orderId.present) {
      map['order_id'] = Variable<int>(orderId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (printCount.present) {
      map['print_count'] = Variable<int>(printCount.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (isPaid.present) {
      map['is_paid'] = Variable<bool>(isPaid.value);
    }
    if (isSynced.present) {
      map['is_synced'] = Variable<bool>(isSynced.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TicketsCompanion(')
          ..write('id: $id, ')
          ..write('num: $num, ')
          ..write('date: $date, ')
          ..write('orderId: $orderId, ')
          ..write('sessionId: $sessionId, ')
          ..write('printCount: $printCount, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('amount: $amount, ')
          ..write('isPaid: $isPaid, ')
          ..write('isSynced: $isSynced, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $PendingSyncOperationsTable extends PendingSyncOperations
    with TableInfo<$PendingSyncOperationsTable, PendingSyncOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingSyncOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _operationTypeMeta = const VerificationMeta(
    'operationType',
  );
  @override
  late final GeneratedColumn<String> operationType = GeneratedColumn<String>(
    'operation_type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 10,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityTypeMeta = const VerificationMeta(
    'entityType',
  );
  @override
  late final GeneratedColumn<String> entityType = GeneratedColumn<String>(
    'entity_type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 50,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<int> entityId = GeneratedColumn<int>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _orderCodeMeta = const VerificationMeta(
    'orderCode',
  );
  @override
  late final GeneratedColumn<String> orderCode = GeneratedColumn<String>(
    'order_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ticketNumMeta = const VerificationMeta(
    'ticketNum',
  );
  @override
  late final GeneratedColumn<String> ticketNum = GeneratedColumn<String>(
    'ticket_num',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updateDataMeta = const VerificationMeta(
    'updateData',
  );
  @override
  late final GeneratedColumn<String> updateData = GeneratedColumn<String>(
    'update_data',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    operationType,
    entityType,
    entityId,
    serverId,
    orderCode,
    ticketNum,
    updateData,
    createdAt,
    retryCount,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_sync_operations';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingSyncOperation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('operation_type')) {
      context.handle(
        _operationTypeMeta,
        operationType.isAcceptableOrUnknown(
          data['operation_type']!,
          _operationTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationTypeMeta);
    }
    if (data.containsKey('entity_type')) {
      context.handle(
        _entityTypeMeta,
        entityType.isAcceptableOrUnknown(data['entity_type']!, _entityTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_entityTypeMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    if (data.containsKey('order_code')) {
      context.handle(
        _orderCodeMeta,
        orderCode.isAcceptableOrUnknown(data['order_code']!, _orderCodeMeta),
      );
    }
    if (data.containsKey('ticket_num')) {
      context.handle(
        _ticketNumMeta,
        ticketNum.isAcceptableOrUnknown(data['ticket_num']!, _ticketNumMeta),
      );
    }
    if (data.containsKey('update_data')) {
      context.handle(
        _updateDataMeta,
        updateData.isAcceptableOrUnknown(data['update_data']!, _updateDataMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingSyncOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingSyncOperation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      operationType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_type'],
      )!,
      entityType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_type'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}entity_id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_id'],
      ),
      orderCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}order_code'],
      ),
      ticketNum: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ticket_num'],
      ),
      updateData: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}update_data'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $PendingSyncOperationsTable createAlias(String alias) {
    return $PendingSyncOperationsTable(attachedDatabase, alias);
  }
}

class PendingSyncOperation extends DataClass
    implements Insertable<PendingSyncOperation> {
  final int id;

  /// Type of operation: 'DELETE' or 'UPDATE'
  final String operationType;

  /// Entity type: 'ORDER', 'TICKET', 'ORDER_PRODUCT', etc.
  final String entityType;

  /// ID of the entity to delete/update (local database ID)
  final int entityId;

  /// Server ID if available (for entities already synced) - DEPRECATED, use orderCode/ticketNum
  final int? serverId;

  /// Order code for identifying orders on server (unique identifier)
  final String? orderCode;

  /// Ticket num for identifying tickets on server (used with orderCode)
  final String? ticketNum;

  /// JSON data for UPDATE operations (contains the fields to update)
  final String? updateData;

  /// Timestamp when the operation was queued
  final DateTime createdAt;

  /// Number of retry attempts
  final int retryCount;

  /// Last error message if sync failed
  final String? lastError;
  const PendingSyncOperation({
    required this.id,
    required this.operationType,
    required this.entityType,
    required this.entityId,
    this.serverId,
    this.orderCode,
    this.ticketNum,
    this.updateData,
    required this.createdAt,
    required this.retryCount,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['operation_type'] = Variable<String>(operationType);
    map['entity_type'] = Variable<String>(entityType);
    map['entity_id'] = Variable<int>(entityId);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<int>(serverId);
    }
    if (!nullToAbsent || orderCode != null) {
      map['order_code'] = Variable<String>(orderCode);
    }
    if (!nullToAbsent || ticketNum != null) {
      map['ticket_num'] = Variable<String>(ticketNum);
    }
    if (!nullToAbsent || updateData != null) {
      map['update_data'] = Variable<String>(updateData);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  PendingSyncOperationsCompanion toCompanion(bool nullToAbsent) {
    return PendingSyncOperationsCompanion(
      id: Value(id),
      operationType: Value(operationType),
      entityType: Value(entityType),
      entityId: Value(entityId),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      orderCode: orderCode == null && nullToAbsent
          ? const Value.absent()
          : Value(orderCode),
      ticketNum: ticketNum == null && nullToAbsent
          ? const Value.absent()
          : Value(ticketNum),
      updateData: updateData == null && nullToAbsent
          ? const Value.absent()
          : Value(updateData),
      createdAt: Value(createdAt),
      retryCount: Value(retryCount),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory PendingSyncOperation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingSyncOperation(
      id: serializer.fromJson<int>(json['id']),
      operationType: serializer.fromJson<String>(json['operationType']),
      entityType: serializer.fromJson<String>(json['entityType']),
      entityId: serializer.fromJson<int>(json['entityId']),
      serverId: serializer.fromJson<int?>(json['serverId']),
      orderCode: serializer.fromJson<String?>(json['orderCode']),
      ticketNum: serializer.fromJson<String?>(json['ticketNum']),
      updateData: serializer.fromJson<String?>(json['updateData']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'operationType': serializer.toJson<String>(operationType),
      'entityType': serializer.toJson<String>(entityType),
      'entityId': serializer.toJson<int>(entityId),
      'serverId': serializer.toJson<int?>(serverId),
      'orderCode': serializer.toJson<String?>(orderCode),
      'ticketNum': serializer.toJson<String?>(ticketNum),
      'updateData': serializer.toJson<String?>(updateData),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'retryCount': serializer.toJson<int>(retryCount),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  PendingSyncOperation copyWith({
    int? id,
    String? operationType,
    String? entityType,
    int? entityId,
    Value<int?> serverId = const Value.absent(),
    Value<String?> orderCode = const Value.absent(),
    Value<String?> ticketNum = const Value.absent(),
    Value<String?> updateData = const Value.absent(),
    DateTime? createdAt,
    int? retryCount,
    Value<String?> lastError = const Value.absent(),
  }) => PendingSyncOperation(
    id: id ?? this.id,
    operationType: operationType ?? this.operationType,
    entityType: entityType ?? this.entityType,
    entityId: entityId ?? this.entityId,
    serverId: serverId.present ? serverId.value : this.serverId,
    orderCode: orderCode.present ? orderCode.value : this.orderCode,
    ticketNum: ticketNum.present ? ticketNum.value : this.ticketNum,
    updateData: updateData.present ? updateData.value : this.updateData,
    createdAt: createdAt ?? this.createdAt,
    retryCount: retryCount ?? this.retryCount,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  PendingSyncOperation copyWithCompanion(PendingSyncOperationsCompanion data) {
    return PendingSyncOperation(
      id: data.id.present ? data.id.value : this.id,
      operationType: data.operationType.present
          ? data.operationType.value
          : this.operationType,
      entityType: data.entityType.present
          ? data.entityType.value
          : this.entityType,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      orderCode: data.orderCode.present ? data.orderCode.value : this.orderCode,
      ticketNum: data.ticketNum.present ? data.ticketNum.value : this.ticketNum,
      updateData: data.updateData.present
          ? data.updateData.value
          : this.updateData,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingSyncOperation(')
          ..write('id: $id, ')
          ..write('operationType: $operationType, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('serverId: $serverId, ')
          ..write('orderCode: $orderCode, ')
          ..write('ticketNum: $ticketNum, ')
          ..write('updateData: $updateData, ')
          ..write('createdAt: $createdAt, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    operationType,
    entityType,
    entityId,
    serverId,
    orderCode,
    ticketNum,
    updateData,
    createdAt,
    retryCount,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingSyncOperation &&
          other.id == this.id &&
          other.operationType == this.operationType &&
          other.entityType == this.entityType &&
          other.entityId == this.entityId &&
          other.serverId == this.serverId &&
          other.orderCode == this.orderCode &&
          other.ticketNum == this.ticketNum &&
          other.updateData == this.updateData &&
          other.createdAt == this.createdAt &&
          other.retryCount == this.retryCount &&
          other.lastError == this.lastError);
}

class PendingSyncOperationsCompanion
    extends UpdateCompanion<PendingSyncOperation> {
  final Value<int> id;
  final Value<String> operationType;
  final Value<String> entityType;
  final Value<int> entityId;
  final Value<int?> serverId;
  final Value<String?> orderCode;
  final Value<String?> ticketNum;
  final Value<String?> updateData;
  final Value<DateTime> createdAt;
  final Value<int> retryCount;
  final Value<String?> lastError;
  const PendingSyncOperationsCompanion({
    this.id = const Value.absent(),
    this.operationType = const Value.absent(),
    this.entityType = const Value.absent(),
    this.entityId = const Value.absent(),
    this.serverId = const Value.absent(),
    this.orderCode = const Value.absent(),
    this.ticketNum = const Value.absent(),
    this.updateData = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  PendingSyncOperationsCompanion.insert({
    this.id = const Value.absent(),
    required String operationType,
    required String entityType,
    required int entityId,
    this.serverId = const Value.absent(),
    this.orderCode = const Value.absent(),
    this.ticketNum = const Value.absent(),
    this.updateData = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastError = const Value.absent(),
  }) : operationType = Value(operationType),
       entityType = Value(entityType),
       entityId = Value(entityId);
  static Insertable<PendingSyncOperation> custom({
    Expression<int>? id,
    Expression<String>? operationType,
    Expression<String>? entityType,
    Expression<int>? entityId,
    Expression<int>? serverId,
    Expression<String>? orderCode,
    Expression<String>? ticketNum,
    Expression<String>? updateData,
    Expression<DateTime>? createdAt,
    Expression<int>? retryCount,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (operationType != null) 'operation_type': operationType,
      if (entityType != null) 'entity_type': entityType,
      if (entityId != null) 'entity_id': entityId,
      if (serverId != null) 'server_id': serverId,
      if (orderCode != null) 'order_code': orderCode,
      if (ticketNum != null) 'ticket_num': ticketNum,
      if (updateData != null) 'update_data': updateData,
      if (createdAt != null) 'created_at': createdAt,
      if (retryCount != null) 'retry_count': retryCount,
      if (lastError != null) 'last_error': lastError,
    });
  }

  PendingSyncOperationsCompanion copyWith({
    Value<int>? id,
    Value<String>? operationType,
    Value<String>? entityType,
    Value<int>? entityId,
    Value<int?>? serverId,
    Value<String?>? orderCode,
    Value<String?>? ticketNum,
    Value<String?>? updateData,
    Value<DateTime>? createdAt,
    Value<int>? retryCount,
    Value<String?>? lastError,
  }) {
    return PendingSyncOperationsCompanion(
      id: id ?? this.id,
      operationType: operationType ?? this.operationType,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      serverId: serverId ?? this.serverId,
      orderCode: orderCode ?? this.orderCode,
      ticketNum: ticketNum ?? this.ticketNum,
      updateData: updateData ?? this.updateData,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (operationType.present) {
      map['operation_type'] = Variable<String>(operationType.value);
    }
    if (entityType.present) {
      map['entity_type'] = Variable<String>(entityType.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<int>(entityId.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (orderCode.present) {
      map['order_code'] = Variable<String>(orderCode.value);
    }
    if (ticketNum.present) {
      map['ticket_num'] = Variable<String>(ticketNum.value);
    }
    if (updateData.present) {
      map['update_data'] = Variable<String>(updateData.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingSyncOperationsCompanion(')
          ..write('id: $id, ')
          ..write('operationType: $operationType, ')
          ..write('entityType: $entityType, ')
          ..write('entityId: $entityId, ')
          ..write('serverId: $serverId, ')
          ..write('orderCode: $orderCode, ')
          ..write('ticketNum: $ticketNum, ')
          ..write('updateData: $updateData, ')
          ..write('createdAt: $createdAt, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

class $OrderLogsTable extends OrderLogs
    with TableInfo<$OrderLogsTable, OrderLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OrderLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _orderIdMeta = const VerificationMeta(
    'orderId',
  );
  @override
  late final GeneratedColumn<int> orderId = GeneratedColumn<int>(
    'order_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES orders (id)',
    ),
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orderId,
    action,
    description,
    timestamp,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'order_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<OrderLog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('order_id')) {
      context.handle(
        _orderIdMeta,
        orderId.isAcceptableOrUnknown(data['order_id']!, _orderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orderIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OrderLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OrderLog(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      orderId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}order_id'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
    );
  }

  @override
  $OrderLogsTable createAlias(String alias) {
    return $OrderLogsTable(attachedDatabase, alias);
  }
}

class OrderLog extends DataClass implements Insertable<OrderLog> {
  final int id;
  final int orderId;
  final String action;
  final String? description;
  final DateTime timestamp;
  const OrderLog({
    required this.id,
    required this.orderId,
    required this.action,
    this.description,
    required this.timestamp,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['order_id'] = Variable<int>(orderId);
    map['action'] = Variable<String>(action);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['timestamp'] = Variable<DateTime>(timestamp);
    return map;
  }

  OrderLogsCompanion toCompanion(bool nullToAbsent) {
    return OrderLogsCompanion(
      id: Value(id),
      orderId: Value(orderId),
      action: Value(action),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      timestamp: Value(timestamp),
    );
  }

  factory OrderLog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OrderLog(
      id: serializer.fromJson<int>(json['id']),
      orderId: serializer.fromJson<int>(json['orderId']),
      action: serializer.fromJson<String>(json['action']),
      description: serializer.fromJson<String?>(json['description']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'orderId': serializer.toJson<int>(orderId),
      'action': serializer.toJson<String>(action),
      'description': serializer.toJson<String?>(description),
      'timestamp': serializer.toJson<DateTime>(timestamp),
    };
  }

  OrderLog copyWith({
    int? id,
    int? orderId,
    String? action,
    Value<String?> description = const Value.absent(),
    DateTime? timestamp,
  }) => OrderLog(
    id: id ?? this.id,
    orderId: orderId ?? this.orderId,
    action: action ?? this.action,
    description: description.present ? description.value : this.description,
    timestamp: timestamp ?? this.timestamp,
  );
  OrderLog copyWithCompanion(OrderLogsCompanion data) {
    return OrderLog(
      id: data.id.present ? data.id.value : this.id,
      orderId: data.orderId.present ? data.orderId.value : this.orderId,
      action: data.action.present ? data.action.value : this.action,
      description: data.description.present
          ? data.description.value
          : this.description,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OrderLog(')
          ..write('id: $id, ')
          ..write('orderId: $orderId, ')
          ..write('action: $action, ')
          ..write('description: $description, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, orderId, action, description, timestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OrderLog &&
          other.id == this.id &&
          other.orderId == this.orderId &&
          other.action == this.action &&
          other.description == this.description &&
          other.timestamp == this.timestamp);
}

class OrderLogsCompanion extends UpdateCompanion<OrderLog> {
  final Value<int> id;
  final Value<int> orderId;
  final Value<String> action;
  final Value<String?> description;
  final Value<DateTime> timestamp;
  const OrderLogsCompanion({
    this.id = const Value.absent(),
    this.orderId = const Value.absent(),
    this.action = const Value.absent(),
    this.description = const Value.absent(),
    this.timestamp = const Value.absent(),
  });
  OrderLogsCompanion.insert({
    this.id = const Value.absent(),
    required int orderId,
    required String action,
    this.description = const Value.absent(),
    this.timestamp = const Value.absent(),
  }) : orderId = Value(orderId),
       action = Value(action);
  static Insertable<OrderLog> custom({
    Expression<int>? id,
    Expression<int>? orderId,
    Expression<String>? action,
    Expression<String>? description,
    Expression<DateTime>? timestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orderId != null) 'order_id': orderId,
      if (action != null) 'action': action,
      if (description != null) 'description': description,
      if (timestamp != null) 'timestamp': timestamp,
    });
  }

  OrderLogsCompanion copyWith({
    Value<int>? id,
    Value<int>? orderId,
    Value<String>? action,
    Value<String?>? description,
    Value<DateTime>? timestamp,
  }) {
    return OrderLogsCompanion(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      action: action ?? this.action,
      description: description ?? this.description,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (orderId.present) {
      map['order_id'] = Variable<int>(orderId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OrderLogsCompanion(')
          ..write('id: $id, ')
          ..write('orderId: $orderId, ')
          ..write('action: $action, ')
          ..write('description: $description, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }
}

class $WaitersTable extends Waiters with TableInfo<$WaitersTable, Waiter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WaitersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _firstNameMeta = const VerificationMeta(
    'firstName',
  );
  @override
  late final GeneratedColumn<String> firstName = GeneratedColumn<String>(
    'first_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastNameMeta = const VerificationMeta(
    'lastName',
  );
  @override
  late final GeneratedColumn<String> lastName = GeneratedColumn<String>(
    'last_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _passwordHashMeta = const VerificationMeta(
    'passwordHash',
  );
  @override
  late final GeneratedColumn<String> passwordHash = GeneratedColumn<String>(
    'password_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    firstName,
    lastName,
    imageUrl,
    username,
    passwordHash,
    isActive,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'waiters';
  @override
  VerificationContext validateIntegrity(
    Insertable<Waiter> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('first_name')) {
      context.handle(
        _firstNameMeta,
        firstName.isAcceptableOrUnknown(data['first_name']!, _firstNameMeta),
      );
    } else if (isInserting) {
      context.missing(_firstNameMeta);
    }
    if (data.containsKey('last_name')) {
      context.handle(
        _lastNameMeta,
        lastName.isAcceptableOrUnknown(data['last_name']!, _lastNameMeta),
      );
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('password_hash')) {
      context.handle(
        _passwordHashMeta,
        passwordHash.isAcceptableOrUnknown(
          data['password_hash']!,
          _passwordHashMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Waiter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Waiter(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      firstName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_name'],
      )!,
      lastName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_name'],
      ),
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      ),
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      ),
      passwordHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password_hash'],
      ),
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WaitersTable createAlias(String alias) {
    return $WaitersTable(attachedDatabase, alias);
  }
}

class Waiter extends DataClass implements Insertable<Waiter> {
  final int id;
  final String firstName;
  final String? lastName;
  final String? imageUrl;
  final String? username;
  final String? passwordHash;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Waiter({
    required this.id,
    required this.firstName,
    this.lastName,
    this.imageUrl,
    this.username,
    this.passwordHash,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['first_name'] = Variable<String>(firstName);
    if (!nullToAbsent || lastName != null) {
      map['last_name'] = Variable<String>(lastName);
    }
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    if (!nullToAbsent || username != null) {
      map['username'] = Variable<String>(username);
    }
    if (!nullToAbsent || passwordHash != null) {
      map['password_hash'] = Variable<String>(passwordHash);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  WaitersCompanion toCompanion(bool nullToAbsent) {
    return WaitersCompanion(
      id: Value(id),
      firstName: Value(firstName),
      lastName: lastName == null && nullToAbsent
          ? const Value.absent()
          : Value(lastName),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      username: username == null && nullToAbsent
          ? const Value.absent()
          : Value(username),
      passwordHash: passwordHash == null && nullToAbsent
          ? const Value.absent()
          : Value(passwordHash),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Waiter.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Waiter(
      id: serializer.fromJson<int>(json['id']),
      firstName: serializer.fromJson<String>(json['firstName']),
      lastName: serializer.fromJson<String?>(json['lastName']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      username: serializer.fromJson<String?>(json['username']),
      passwordHash: serializer.fromJson<String?>(json['passwordHash']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'firstName': serializer.toJson<String>(firstName),
      'lastName': serializer.toJson<String?>(lastName),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'username': serializer.toJson<String?>(username),
      'passwordHash': serializer.toJson<String?>(passwordHash),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Waiter copyWith({
    int? id,
    String? firstName,
    Value<String?> lastName = const Value.absent(),
    Value<String?> imageUrl = const Value.absent(),
    Value<String?> username = const Value.absent(),
    Value<String?> passwordHash = const Value.absent(),
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Waiter(
    id: id ?? this.id,
    firstName: firstName ?? this.firstName,
    lastName: lastName.present ? lastName.value : this.lastName,
    imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
    username: username.present ? username.value : this.username,
    passwordHash: passwordHash.present ? passwordHash.value : this.passwordHash,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Waiter copyWithCompanion(WaitersCompanion data) {
    return Waiter(
      id: data.id.present ? data.id.value : this.id,
      firstName: data.firstName.present ? data.firstName.value : this.firstName,
      lastName: data.lastName.present ? data.lastName.value : this.lastName,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      username: data.username.present ? data.username.value : this.username,
      passwordHash: data.passwordHash.present
          ? data.passwordHash.value
          : this.passwordHash,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Waiter(')
          ..write('id: $id, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('username: $username, ')
          ..write('passwordHash: $passwordHash, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    firstName,
    lastName,
    imageUrl,
    username,
    passwordHash,
    isActive,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Waiter &&
          other.id == this.id &&
          other.firstName == this.firstName &&
          other.lastName == this.lastName &&
          other.imageUrl == this.imageUrl &&
          other.username == this.username &&
          other.passwordHash == this.passwordHash &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class WaitersCompanion extends UpdateCompanion<Waiter> {
  final Value<int> id;
  final Value<String> firstName;
  final Value<String?> lastName;
  final Value<String?> imageUrl;
  final Value<String?> username;
  final Value<String?> passwordHash;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const WaitersCompanion({
    this.id = const Value.absent(),
    this.firstName = const Value.absent(),
    this.lastName = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.username = const Value.absent(),
    this.passwordHash = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  WaitersCompanion.insert({
    this.id = const Value.absent(),
    required String firstName,
    this.lastName = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.username = const Value.absent(),
    this.passwordHash = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : firstName = Value(firstName);
  static Insertable<Waiter> custom({
    Expression<int>? id,
    Expression<String>? firstName,
    Expression<String>? lastName,
    Expression<String>? imageUrl,
    Expression<String>? username,
    Expression<String>? passwordHash,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (imageUrl != null) 'image_url': imageUrl,
      if (username != null) 'username': username,
      if (passwordHash != null) 'password_hash': passwordHash,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  WaitersCompanion copyWith({
    Value<int>? id,
    Value<String>? firstName,
    Value<String?>? lastName,
    Value<String?>? imageUrl,
    Value<String?>? username,
    Value<String?>? passwordHash,
    Value<bool>? isActive,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return WaitersCompanion(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      imageUrl: imageUrl ?? this.imageUrl,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (firstName.present) {
      map['first_name'] = Variable<String>(firstName.value);
    }
    if (lastName.present) {
      map['last_name'] = Variable<String>(lastName.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (passwordHash.present) {
      map['password_hash'] = Variable<String>(passwordHash.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WaitersCompanion(')
          ..write('id: $id, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('username: $username, ')
          ..write('passwordHash: $passwordHash, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $WaiterAreasTable extends WaiterAreas
    with TableInfo<$WaiterAreasTable, WaiterArea> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WaiterAreasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _waiterIdMeta = const VerificationMeta(
    'waiterId',
  );
  @override
  late final GeneratedColumn<int> waiterId = GeneratedColumn<int>(
    'waiter_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _areaIdMeta = const VerificationMeta('areaId');
  @override
  late final GeneratedColumn<int> areaId = GeneratedColumn<int>(
    'area_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [waiterId, areaId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'waiter_areas';
  @override
  VerificationContext validateIntegrity(
    Insertable<WaiterArea> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('waiter_id')) {
      context.handle(
        _waiterIdMeta,
        waiterId.isAcceptableOrUnknown(data['waiter_id']!, _waiterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_waiterIdMeta);
    }
    if (data.containsKey('area_id')) {
      context.handle(
        _areaIdMeta,
        areaId.isAcceptableOrUnknown(data['area_id']!, _areaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_areaIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {waiterId, areaId};
  @override
  WaiterArea map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WaiterArea(
      waiterId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}waiter_id'],
      )!,
      areaId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}area_id'],
      )!,
    );
  }

  @override
  $WaiterAreasTable createAlias(String alias) {
    return $WaiterAreasTable(attachedDatabase, alias);
  }
}

class WaiterArea extends DataClass implements Insertable<WaiterArea> {
  final int waiterId;
  final int areaId;
  const WaiterArea({required this.waiterId, required this.areaId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['waiter_id'] = Variable<int>(waiterId);
    map['area_id'] = Variable<int>(areaId);
    return map;
  }

  WaiterAreasCompanion toCompanion(bool nullToAbsent) {
    return WaiterAreasCompanion(
      waiterId: Value(waiterId),
      areaId: Value(areaId),
    );
  }

  factory WaiterArea.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WaiterArea(
      waiterId: serializer.fromJson<int>(json['waiterId']),
      areaId: serializer.fromJson<int>(json['areaId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'waiterId': serializer.toJson<int>(waiterId),
      'areaId': serializer.toJson<int>(areaId),
    };
  }

  WaiterArea copyWith({int? waiterId, int? areaId}) => WaiterArea(
    waiterId: waiterId ?? this.waiterId,
    areaId: areaId ?? this.areaId,
  );
  WaiterArea copyWithCompanion(WaiterAreasCompanion data) {
    return WaiterArea(
      waiterId: data.waiterId.present ? data.waiterId.value : this.waiterId,
      areaId: data.areaId.present ? data.areaId.value : this.areaId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WaiterArea(')
          ..write('waiterId: $waiterId, ')
          ..write('areaId: $areaId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(waiterId, areaId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WaiterArea &&
          other.waiterId == this.waiterId &&
          other.areaId == this.areaId);
}

class WaiterAreasCompanion extends UpdateCompanion<WaiterArea> {
  final Value<int> waiterId;
  final Value<int> areaId;
  final Value<int> rowid;
  const WaiterAreasCompanion({
    this.waiterId = const Value.absent(),
    this.areaId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WaiterAreasCompanion.insert({
    required int waiterId,
    required int areaId,
    this.rowid = const Value.absent(),
  }) : waiterId = Value(waiterId),
       areaId = Value(areaId);
  static Insertable<WaiterArea> custom({
    Expression<int>? waiterId,
    Expression<int>? areaId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (waiterId != null) 'waiter_id': waiterId,
      if (areaId != null) 'area_id': areaId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WaiterAreasCompanion copyWith({
    Value<int>? waiterId,
    Value<int>? areaId,
    Value<int>? rowid,
  }) {
    return WaiterAreasCompanion(
      waiterId: waiterId ?? this.waiterId,
      areaId: areaId ?? this.areaId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (waiterId.present) {
      map['waiter_id'] = Variable<int>(waiterId.value);
    }
    if (areaId.present) {
      map['area_id'] = Variable<int>(areaId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WaiterAreasCompanion(')
          ..write('waiterId: $waiterId, ')
          ..write('areaId: $areaId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $ProductsTable products = $ProductsTable(this);
  late final $ProductVariantsTable productVariants = $ProductVariantsTable(
    this,
  );
  late final $VariantAttributeValuesTable variantAttributeValues =
      $VariantAttributeValuesTable(this);
  late final $UsersTable users = $UsersTable(this);
  late final $ComponentsTable components = $ComponentsTable(this);
  late final $ComponentGroupsTable componentGroups = $ComponentGroupsTable(
    this,
  );
  late final $ProductComponentsTable productComponents =
      $ProductComponentsTable(this);
  late final $AreasTable areas = $AreasTable(this);
  late final $AreaTablesTable areaTables = $AreaTablesTable(this);
  late final $StationsTable stations = $StationsTable(this);
  late final $KiosksTable kiosks = $KiosksTable(this);
  late final $KDSsTable kDSs = $KDSsTable(this);
  late final $CommercialsTable commercials = $CommercialsTable(this);
  late final $CustomersTable customers = $CustomersTable(this);
  late final $OrdersTable orders = $OrdersTable(this);
  late final $OrderProductsTable orderProducts = $OrderProductsTable(this);
  late final $OrderProductComponentsTable orderProductComponents =
      $OrderProductComponentsTable(this);
  late final $PaymentsTable payments = $PaymentsTable(this);
  late final $TransactionsTable transactions = $TransactionsTable(this);
  late final $CashSessionsTable cashSessions = $CashSessionsTable(this);
  late final $TicketsTable tickets = $TicketsTable(this);
  late final $PendingSyncOperationsTable pendingSyncOperations =
      $PendingSyncOperationsTable(this);
  late final $OrderLogsTable orderLogs = $OrderLogsTable(this);
  late final $WaitersTable waiters = $WaitersTable(this);
  late final $WaiterAreasTable waiterAreas = $WaiterAreasTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    categories,
    products,
    productVariants,
    variantAttributeValues,
    users,
    components,
    componentGroups,
    productComponents,
    areas,
    areaTables,
    stations,
    kiosks,
    kDSs,
    commercials,
    customers,
    orders,
    orderProducts,
    orderProductComponents,
    payments,
    transactions,
    cashSessions,
    tickets,
    pendingSyncOperations,
    orderLogs,
    waiters,
    waiterAreas,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'orders',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('tickets', kind: UpdateKind.delete)],
    ),
  ]);
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      Value<int> id,
      required String name,
      Value<String?> imageUrl,
      Value<String?> description,
      Value<int> displayOrder,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> imageUrl,
      Value<String?> description,
      Value<int> displayOrder,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          Category,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
          Category,
          PrefetchHooks Function()
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                name: name,
                imageUrl: imageUrl,
                description: description,
                displayOrder: displayOrder,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String?> imageUrl = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                name: name,
                imageUrl: imageUrl,
                description: description,
                displayOrder: displayOrder,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      Category,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
      Category,
      PrefetchHooks Function()
    >;
typedef $$ProductsTableCreateCompanionBuilder =
    ProductsCompanion Function({
      Value<int> id,
      required String name,
      Value<String?> barcode,
      Value<String?> imageUrl,
      Value<String?> description,
      required double price,
      Value<String> uom,
      Value<int?> categoryId,
      Value<int?> stationId,
      Value<double> tvaAmount,
      Value<double> discountAmount,
      required double finalPrice,
      Value<bool> isActive,
      Value<bool> isVariant,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$ProductsTableUpdateCompanionBuilder =
    ProductsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> barcode,
      Value<String?> imageUrl,
      Value<String?> description,
      Value<double> price,
      Value<String> uom,
      Value<int?> categoryId,
      Value<int?> stationId,
      Value<double> tvaAmount,
      Value<double> discountAmount,
      Value<double> finalPrice,
      Value<bool> isActive,
      Value<bool> isVariant,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$ProductsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uom => $composableBuilder(
    column: $table.uom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get tvaAmount => $composableBuilder(
    column: $table.tvaAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get discountAmount => $composableBuilder(
    column: $table.discountAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get finalPrice => $composableBuilder(
    column: $table.finalPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isVariant => $composableBuilder(
    column: $table.isVariant,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProductsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uom => $composableBuilder(
    column: $table.uom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get tvaAmount => $composableBuilder(
    column: $table.tvaAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get discountAmount => $composableBuilder(
    column: $table.discountAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get finalPrice => $composableBuilder(
    column: $table.finalPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isVariant => $composableBuilder(
    column: $table.isVariant,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProductsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get barcode =>
      $composableBuilder(column: $table.barcode, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<String> get uom =>
      $composableBuilder(column: $table.uom, builder: (column) => column);

  GeneratedColumn<int> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<double> get tvaAmount =>
      $composableBuilder(column: $table.tvaAmount, builder: (column) => column);

  GeneratedColumn<double> get discountAmount => $composableBuilder(
    column: $table.discountAmount,
    builder: (column) => column,
  );

  GeneratedColumn<double> get finalPrice => $composableBuilder(
    column: $table.finalPrice,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<bool> get isVariant =>
      $composableBuilder(column: $table.isVariant, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ProductsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProductsTable,
          Product,
          $$ProductsTableFilterComposer,
          $$ProductsTableOrderingComposer,
          $$ProductsTableAnnotationComposer,
          $$ProductsTableCreateCompanionBuilder,
          $$ProductsTableUpdateCompanionBuilder,
          (Product, BaseReferences<_$AppDatabase, $ProductsTable, Product>),
          Product,
          PrefetchHooks Function()
        > {
  $$ProductsTableTableManager(_$AppDatabase db, $ProductsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> barcode = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<double> price = const Value.absent(),
                Value<String> uom = const Value.absent(),
                Value<int?> categoryId = const Value.absent(),
                Value<int?> stationId = const Value.absent(),
                Value<double> tvaAmount = const Value.absent(),
                Value<double> discountAmount = const Value.absent(),
                Value<double> finalPrice = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<bool> isVariant = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ProductsCompanion(
                id: id,
                name: name,
                barcode: barcode,
                imageUrl: imageUrl,
                description: description,
                price: price,
                uom: uom,
                categoryId: categoryId,
                stationId: stationId,
                tvaAmount: tvaAmount,
                discountAmount: discountAmount,
                finalPrice: finalPrice,
                isActive: isActive,
                isVariant: isVariant,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String?> barcode = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<String?> description = const Value.absent(),
                required double price,
                Value<String> uom = const Value.absent(),
                Value<int?> categoryId = const Value.absent(),
                Value<int?> stationId = const Value.absent(),
                Value<double> tvaAmount = const Value.absent(),
                Value<double> discountAmount = const Value.absent(),
                required double finalPrice,
                Value<bool> isActive = const Value.absent(),
                Value<bool> isVariant = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ProductsCompanion.insert(
                id: id,
                name: name,
                barcode: barcode,
                imageUrl: imageUrl,
                description: description,
                price: price,
                uom: uom,
                categoryId: categoryId,
                stationId: stationId,
                tvaAmount: tvaAmount,
                discountAmount: discountAmount,
                finalPrice: finalPrice,
                isActive: isActive,
                isVariant: isVariant,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProductsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProductsTable,
      Product,
      $$ProductsTableFilterComposer,
      $$ProductsTableOrderingComposer,
      $$ProductsTableAnnotationComposer,
      $$ProductsTableCreateCompanionBuilder,
      $$ProductsTableUpdateCompanionBuilder,
      (Product, BaseReferences<_$AppDatabase, $ProductsTable, Product>),
      Product,
      PrefetchHooks Function()
    >;
typedef $$ProductVariantsTableCreateCompanionBuilder =
    ProductVariantsCompanion Function({
      Value<int> id,
      required int productId,
      required String name,
      Value<String?> barcode,
      Value<String?> sku,
      Value<String?> description,
      Value<String?> imageUrl,
      Value<String?> color,
      Value<String?> tags,
      required double price,
      Value<double?> cost,
      Value<double> tvaAmount,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$ProductVariantsTableUpdateCompanionBuilder =
    ProductVariantsCompanion Function({
      Value<int> id,
      Value<int> productId,
      Value<String> name,
      Value<String?> barcode,
      Value<String?> sku,
      Value<String?> description,
      Value<String?> imageUrl,
      Value<String?> color,
      Value<String?> tags,
      Value<double> price,
      Value<double?> cost,
      Value<double> tvaAmount,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$ProductVariantsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductVariantsTable> {
  $$ProductVariantsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cost => $composableBuilder(
    column: $table.cost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get tvaAmount => $composableBuilder(
    column: $table.tvaAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProductVariantsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductVariantsTable> {
  $$ProductVariantsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cost => $composableBuilder(
    column: $table.cost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get tvaAmount => $composableBuilder(
    column: $table.tvaAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProductVariantsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductVariantsTable> {
  $$ProductVariantsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get barcode =>
      $composableBuilder(column: $table.barcode, builder: (column) => column);

  GeneratedColumn<String> get sku =>
      $composableBuilder(column: $table.sku, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<double> get cost =>
      $composableBuilder(column: $table.cost, builder: (column) => column);

  GeneratedColumn<double> get tvaAmount =>
      $composableBuilder(column: $table.tvaAmount, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ProductVariantsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProductVariantsTable,
          ProductVariant,
          $$ProductVariantsTableFilterComposer,
          $$ProductVariantsTableOrderingComposer,
          $$ProductVariantsTableAnnotationComposer,
          $$ProductVariantsTableCreateCompanionBuilder,
          $$ProductVariantsTableUpdateCompanionBuilder,
          (
            ProductVariant,
            BaseReferences<
              _$AppDatabase,
              $ProductVariantsTable,
              ProductVariant
            >,
          ),
          ProductVariant,
          PrefetchHooks Function()
        > {
  $$ProductVariantsTableTableManager(
    _$AppDatabase db,
    $ProductVariantsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductVariantsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductVariantsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductVariantsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> productId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> barcode = const Value.absent(),
                Value<String?> sku = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<String?> tags = const Value.absent(),
                Value<double> price = const Value.absent(),
                Value<double?> cost = const Value.absent(),
                Value<double> tvaAmount = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ProductVariantsCompanion(
                id: id,
                productId: productId,
                name: name,
                barcode: barcode,
                sku: sku,
                description: description,
                imageUrl: imageUrl,
                color: color,
                tags: tags,
                price: price,
                cost: cost,
                tvaAmount: tvaAmount,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int productId,
                required String name,
                Value<String?> barcode = const Value.absent(),
                Value<String?> sku = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<String?> tags = const Value.absent(),
                required double price,
                Value<double?> cost = const Value.absent(),
                Value<double> tvaAmount = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ProductVariantsCompanion.insert(
                id: id,
                productId: productId,
                name: name,
                barcode: barcode,
                sku: sku,
                description: description,
                imageUrl: imageUrl,
                color: color,
                tags: tags,
                price: price,
                cost: cost,
                tvaAmount: tvaAmount,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProductVariantsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProductVariantsTable,
      ProductVariant,
      $$ProductVariantsTableFilterComposer,
      $$ProductVariantsTableOrderingComposer,
      $$ProductVariantsTableAnnotationComposer,
      $$ProductVariantsTableCreateCompanionBuilder,
      $$ProductVariantsTableUpdateCompanionBuilder,
      (
        ProductVariant,
        BaseReferences<_$AppDatabase, $ProductVariantsTable, ProductVariant>,
      ),
      ProductVariant,
      PrefetchHooks Function()
    >;
typedef $$VariantAttributeValuesTableCreateCompanionBuilder =
    VariantAttributeValuesCompanion Function({
      Value<int> id,
      required int variantId,
      required int attributeId,
      Value<String?> attributeName,
      required int valueId,
      Value<String?> value,
      Value<DateTime> createdAt,
    });
typedef $$VariantAttributeValuesTableUpdateCompanionBuilder =
    VariantAttributeValuesCompanion Function({
      Value<int> id,
      Value<int> variantId,
      Value<int> attributeId,
      Value<String?> attributeName,
      Value<int> valueId,
      Value<String?> value,
      Value<DateTime> createdAt,
    });

class $$VariantAttributeValuesTableFilterComposer
    extends Composer<_$AppDatabase, $VariantAttributeValuesTable> {
  $$VariantAttributeValuesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get variantId => $composableBuilder(
    column: $table.variantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attributeId => $composableBuilder(
    column: $table.attributeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attributeName => $composableBuilder(
    column: $table.attributeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get valueId => $composableBuilder(
    column: $table.valueId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VariantAttributeValuesTableOrderingComposer
    extends Composer<_$AppDatabase, $VariantAttributeValuesTable> {
  $$VariantAttributeValuesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get variantId => $composableBuilder(
    column: $table.variantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attributeId => $composableBuilder(
    column: $table.attributeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attributeName => $composableBuilder(
    column: $table.attributeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get valueId => $composableBuilder(
    column: $table.valueId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VariantAttributeValuesTableAnnotationComposer
    extends Composer<_$AppDatabase, $VariantAttributeValuesTable> {
  $$VariantAttributeValuesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get variantId =>
      $composableBuilder(column: $table.variantId, builder: (column) => column);

  GeneratedColumn<int> get attributeId => $composableBuilder(
    column: $table.attributeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attributeName => $composableBuilder(
    column: $table.attributeName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get valueId =>
      $composableBuilder(column: $table.valueId, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$VariantAttributeValuesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VariantAttributeValuesTable,
          VariantAttributeValue,
          $$VariantAttributeValuesTableFilterComposer,
          $$VariantAttributeValuesTableOrderingComposer,
          $$VariantAttributeValuesTableAnnotationComposer,
          $$VariantAttributeValuesTableCreateCompanionBuilder,
          $$VariantAttributeValuesTableUpdateCompanionBuilder,
          (
            VariantAttributeValue,
            BaseReferences<
              _$AppDatabase,
              $VariantAttributeValuesTable,
              VariantAttributeValue
            >,
          ),
          VariantAttributeValue,
          PrefetchHooks Function()
        > {
  $$VariantAttributeValuesTableTableManager(
    _$AppDatabase db,
    $VariantAttributeValuesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VariantAttributeValuesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$VariantAttributeValuesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$VariantAttributeValuesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> variantId = const Value.absent(),
                Value<int> attributeId = const Value.absent(),
                Value<String?> attributeName = const Value.absent(),
                Value<int> valueId = const Value.absent(),
                Value<String?> value = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => VariantAttributeValuesCompanion(
                id: id,
                variantId: variantId,
                attributeId: attributeId,
                attributeName: attributeName,
                valueId: valueId,
                value: value,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int variantId,
                required int attributeId,
                Value<String?> attributeName = const Value.absent(),
                required int valueId,
                Value<String?> value = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => VariantAttributeValuesCompanion.insert(
                id: id,
                variantId: variantId,
                attributeId: attributeId,
                attributeName: attributeName,
                valueId: valueId,
                value: value,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VariantAttributeValuesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VariantAttributeValuesTable,
      VariantAttributeValue,
      $$VariantAttributeValuesTableFilterComposer,
      $$VariantAttributeValuesTableOrderingComposer,
      $$VariantAttributeValuesTableAnnotationComposer,
      $$VariantAttributeValuesTableCreateCompanionBuilder,
      $$VariantAttributeValuesTableUpdateCompanionBuilder,
      (
        VariantAttributeValue,
        BaseReferences<
          _$AppDatabase,
          $VariantAttributeValuesTable,
          VariantAttributeValue
        >,
      ),
      VariantAttributeValue,
      PrefetchHooks Function()
    >;
typedef $$UsersTableCreateCompanionBuilder =
    UsersCompanion Function({
      Value<int> id,
      required String username,
      required String password,
      required String firstName,
      required String lastName,
      required String type,
      Value<String?> imageUrl,
      Value<String?> accessToken,
      Value<String?> refreshToken,
      Value<String?> permissions,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> lastLogin,
    });
typedef $$UsersTableUpdateCompanionBuilder =
    UsersCompanion Function({
      Value<int> id,
      Value<String> username,
      Value<String> password,
      Value<String> firstName,
      Value<String> lastName,
      Value<String> type,
      Value<String?> imageUrl,
      Value<String?> accessToken,
      Value<String?> refreshToken,
      Value<String?> permissions,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> lastLogin,
    });

class $$UsersTableFilterComposer extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get password => $composableBuilder(
    column: $table.password,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accessToken => $composableBuilder(
    column: $table.accessToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refreshToken => $composableBuilder(
    column: $table.refreshToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get permissions => $composableBuilder(
    column: $table.permissions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastLogin => $composableBuilder(
    column: $table.lastLogin,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UsersTableOrderingComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get password => $composableBuilder(
    column: $table.password,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accessToken => $composableBuilder(
    column: $table.accessToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refreshToken => $composableBuilder(
    column: $table.refreshToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get permissions => $composableBuilder(
    column: $table.permissions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastLogin => $composableBuilder(
    column: $table.lastLogin,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UsersTableAnnotationComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get password =>
      $composableBuilder(column: $table.password, builder: (column) => column);

  GeneratedColumn<String> get firstName =>
      $composableBuilder(column: $table.firstName, builder: (column) => column);

  GeneratedColumn<String> get lastName =>
      $composableBuilder(column: $table.lastName, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<String> get accessToken => $composableBuilder(
    column: $table.accessToken,
    builder: (column) => column,
  );

  GeneratedColumn<String> get refreshToken => $composableBuilder(
    column: $table.refreshToken,
    builder: (column) => column,
  );

  GeneratedColumn<String> get permissions => $composableBuilder(
    column: $table.permissions,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastLogin =>
      $composableBuilder(column: $table.lastLogin, builder: (column) => column);
}

class $$UsersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UsersTable,
          User,
          $$UsersTableFilterComposer,
          $$UsersTableOrderingComposer,
          $$UsersTableAnnotationComposer,
          $$UsersTableCreateCompanionBuilder,
          $$UsersTableUpdateCompanionBuilder,
          (User, BaseReferences<_$AppDatabase, $UsersTable, User>),
          User,
          PrefetchHooks Function()
        > {
  $$UsersTableTableManager(_$AppDatabase db, $UsersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> password = const Value.absent(),
                Value<String> firstName = const Value.absent(),
                Value<String> lastName = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<String?> accessToken = const Value.absent(),
                Value<String?> refreshToken = const Value.absent(),
                Value<String?> permissions = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> lastLogin = const Value.absent(),
              }) => UsersCompanion(
                id: id,
                username: username,
                password: password,
                firstName: firstName,
                lastName: lastName,
                type: type,
                imageUrl: imageUrl,
                accessToken: accessToken,
                refreshToken: refreshToken,
                permissions: permissions,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastLogin: lastLogin,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String username,
                required String password,
                required String firstName,
                required String lastName,
                required String type,
                Value<String?> imageUrl = const Value.absent(),
                Value<String?> accessToken = const Value.absent(),
                Value<String?> refreshToken = const Value.absent(),
                Value<String?> permissions = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> lastLogin = const Value.absent(),
              }) => UsersCompanion.insert(
                id: id,
                username: username,
                password: password,
                firstName: firstName,
                lastName: lastName,
                type: type,
                imageUrl: imageUrl,
                accessToken: accessToken,
                refreshToken: refreshToken,
                permissions: permissions,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastLogin: lastLogin,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UsersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UsersTable,
      User,
      $$UsersTableFilterComposer,
      $$UsersTableOrderingComposer,
      $$UsersTableAnnotationComposer,
      $$UsersTableCreateCompanionBuilder,
      $$UsersTableUpdateCompanionBuilder,
      (User, BaseReferences<_$AppDatabase, $UsersTable, User>),
      User,
      PrefetchHooks Function()
    >;
typedef $$ComponentsTableCreateCompanionBuilder =
    ComponentsCompanion Function({
      Value<int> id,
      required String name,
      Value<String?> description,
      Value<String?> imageUrl,
      Value<double> price,
      Value<int?> componentGroupId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$ComponentsTableUpdateCompanionBuilder =
    ComponentsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> description,
      Value<String?> imageUrl,
      Value<double> price,
      Value<int?> componentGroupId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$ComponentsTableFilterComposer
    extends Composer<_$AppDatabase, $ComponentsTable> {
  $$ComponentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get componentGroupId => $composableBuilder(
    column: $table.componentGroupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ComponentsTableOrderingComposer
    extends Composer<_$AppDatabase, $ComponentsTable> {
  $$ComponentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get componentGroupId => $composableBuilder(
    column: $table.componentGroupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ComponentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ComponentsTable> {
  $$ComponentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<int> get componentGroupId => $composableBuilder(
    column: $table.componentGroupId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ComponentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ComponentsTable,
          Component,
          $$ComponentsTableFilterComposer,
          $$ComponentsTableOrderingComposer,
          $$ComponentsTableAnnotationComposer,
          $$ComponentsTableCreateCompanionBuilder,
          $$ComponentsTableUpdateCompanionBuilder,
          (
            Component,
            BaseReferences<_$AppDatabase, $ComponentsTable, Component>,
          ),
          Component,
          PrefetchHooks Function()
        > {
  $$ComponentsTableTableManager(_$AppDatabase db, $ComponentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ComponentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ComponentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ComponentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<double> price = const Value.absent(),
                Value<int?> componentGroupId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ComponentsCompanion(
                id: id,
                name: name,
                description: description,
                imageUrl: imageUrl,
                price: price,
                componentGroupId: componentGroupId,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String?> description = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<double> price = const Value.absent(),
                Value<int?> componentGroupId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ComponentsCompanion.insert(
                id: id,
                name: name,
                description: description,
                imageUrl: imageUrl,
                price: price,
                componentGroupId: componentGroupId,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ComponentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ComponentsTable,
      Component,
      $$ComponentsTableFilterComposer,
      $$ComponentsTableOrderingComposer,
      $$ComponentsTableAnnotationComposer,
      $$ComponentsTableCreateCompanionBuilder,
      $$ComponentsTableUpdateCompanionBuilder,
      (Component, BaseReferences<_$AppDatabase, $ComponentsTable, Component>),
      Component,
      PrefetchHooks Function()
    >;
typedef $$ComponentGroupsTableCreateCompanionBuilder =
    ComponentGroupsCompanion Function({
      Value<int> id,
      required String name,
      Value<int> displayOrder,
      Value<String?> description,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$ComponentGroupsTableUpdateCompanionBuilder =
    ComponentGroupsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<int> displayOrder,
      Value<String?> description,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$ComponentGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $ComponentGroupsTable> {
  $$ComponentGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ComponentGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $ComponentGroupsTable> {
  $$ComponentGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ComponentGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ComponentGroupsTable> {
  $$ComponentGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ComponentGroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ComponentGroupsTable,
          ComponentGroup,
          $$ComponentGroupsTableFilterComposer,
          $$ComponentGroupsTableOrderingComposer,
          $$ComponentGroupsTableAnnotationComposer,
          $$ComponentGroupsTableCreateCompanionBuilder,
          $$ComponentGroupsTableUpdateCompanionBuilder,
          (
            ComponentGroup,
            BaseReferences<
              _$AppDatabase,
              $ComponentGroupsTable,
              ComponentGroup
            >,
          ),
          ComponentGroup,
          PrefetchHooks Function()
        > {
  $$ComponentGroupsTableTableManager(
    _$AppDatabase db,
    $ComponentGroupsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ComponentGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ComponentGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ComponentGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ComponentGroupsCompanion(
                id: id,
                name: name,
                displayOrder: displayOrder,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<int> displayOrder = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ComponentGroupsCompanion.insert(
                id: id,
                name: name,
                displayOrder: displayOrder,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ComponentGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ComponentGroupsTable,
      ComponentGroup,
      $$ComponentGroupsTableFilterComposer,
      $$ComponentGroupsTableOrderingComposer,
      $$ComponentGroupsTableAnnotationComposer,
      $$ComponentGroupsTableCreateCompanionBuilder,
      $$ComponentGroupsTableUpdateCompanionBuilder,
      (
        ComponentGroup,
        BaseReferences<_$AppDatabase, $ComponentGroupsTable, ComponentGroup>,
      ),
      ComponentGroup,
      PrefetchHooks Function()
    >;
typedef $$ProductComponentsTableCreateCompanionBuilder =
    ProductComponentsCompanion Function({
      Value<int> id,
      required int productId,
      required int componentId,
      Value<double> defaultPrice,
      Value<int> defaultQuantity,
      Value<bool> isRequired,
      Value<int> minQuantity,
      Value<int> maxQuantity,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$ProductComponentsTableUpdateCompanionBuilder =
    ProductComponentsCompanion Function({
      Value<int> id,
      Value<int> productId,
      Value<int> componentId,
      Value<double> defaultPrice,
      Value<int> defaultQuantity,
      Value<bool> isRequired,
      Value<int> minQuantity,
      Value<int> maxQuantity,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$ProductComponentsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductComponentsTable> {
  $$ProductComponentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get componentId => $composableBuilder(
    column: $table.componentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get defaultPrice => $composableBuilder(
    column: $table.defaultPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get defaultQuantity => $composableBuilder(
    column: $table.defaultQuantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRequired => $composableBuilder(
    column: $table.isRequired,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minQuantity => $composableBuilder(
    column: $table.minQuantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxQuantity => $composableBuilder(
    column: $table.maxQuantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProductComponentsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductComponentsTable> {
  $$ProductComponentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get componentId => $composableBuilder(
    column: $table.componentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get defaultPrice => $composableBuilder(
    column: $table.defaultPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get defaultQuantity => $composableBuilder(
    column: $table.defaultQuantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRequired => $composableBuilder(
    column: $table.isRequired,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minQuantity => $composableBuilder(
    column: $table.minQuantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxQuantity => $composableBuilder(
    column: $table.maxQuantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProductComponentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductComponentsTable> {
  $$ProductComponentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<int> get componentId => $composableBuilder(
    column: $table.componentId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get defaultPrice => $composableBuilder(
    column: $table.defaultPrice,
    builder: (column) => column,
  );

  GeneratedColumn<int> get defaultQuantity => $composableBuilder(
    column: $table.defaultQuantity,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isRequired => $composableBuilder(
    column: $table.isRequired,
    builder: (column) => column,
  );

  GeneratedColumn<int> get minQuantity => $composableBuilder(
    column: $table.minQuantity,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maxQuantity => $composableBuilder(
    column: $table.maxQuantity,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ProductComponentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProductComponentsTable,
          ProductComponent,
          $$ProductComponentsTableFilterComposer,
          $$ProductComponentsTableOrderingComposer,
          $$ProductComponentsTableAnnotationComposer,
          $$ProductComponentsTableCreateCompanionBuilder,
          $$ProductComponentsTableUpdateCompanionBuilder,
          (
            ProductComponent,
            BaseReferences<
              _$AppDatabase,
              $ProductComponentsTable,
              ProductComponent
            >,
          ),
          ProductComponent,
          PrefetchHooks Function()
        > {
  $$ProductComponentsTableTableManager(
    _$AppDatabase db,
    $ProductComponentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductComponentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductComponentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductComponentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> productId = const Value.absent(),
                Value<int> componentId = const Value.absent(),
                Value<double> defaultPrice = const Value.absent(),
                Value<int> defaultQuantity = const Value.absent(),
                Value<bool> isRequired = const Value.absent(),
                Value<int> minQuantity = const Value.absent(),
                Value<int> maxQuantity = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ProductComponentsCompanion(
                id: id,
                productId: productId,
                componentId: componentId,
                defaultPrice: defaultPrice,
                defaultQuantity: defaultQuantity,
                isRequired: isRequired,
                minQuantity: minQuantity,
                maxQuantity: maxQuantity,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int productId,
                required int componentId,
                Value<double> defaultPrice = const Value.absent(),
                Value<int> defaultQuantity = const Value.absent(),
                Value<bool> isRequired = const Value.absent(),
                Value<int> minQuantity = const Value.absent(),
                Value<int> maxQuantity = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => ProductComponentsCompanion.insert(
                id: id,
                productId: productId,
                componentId: componentId,
                defaultPrice: defaultPrice,
                defaultQuantity: defaultQuantity,
                isRequired: isRequired,
                minQuantity: minQuantity,
                maxQuantity: maxQuantity,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProductComponentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProductComponentsTable,
      ProductComponent,
      $$ProductComponentsTableFilterComposer,
      $$ProductComponentsTableOrderingComposer,
      $$ProductComponentsTableAnnotationComposer,
      $$ProductComponentsTableCreateCompanionBuilder,
      $$ProductComponentsTableUpdateCompanionBuilder,
      (
        ProductComponent,
        BaseReferences<
          _$AppDatabase,
          $ProductComponentsTable,
          ProductComponent
        >,
      ),
      ProductComponent,
      PrefetchHooks Function()
    >;
typedef $$AreasTableCreateCompanionBuilder =
    AreasCompanion Function({
      Value<int> id,
      required String name,
      Value<String?> description,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$AreasTableUpdateCompanionBuilder =
    AreasCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> description,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$AreasTableFilterComposer extends Composer<_$AppDatabase, $AreasTable> {
  $$AreasTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AreasTableOrderingComposer
    extends Composer<_$AppDatabase, $AreasTable> {
  $$AreasTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AreasTableAnnotationComposer
    extends Composer<_$AppDatabase, $AreasTable> {
  $$AreasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AreasTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AreasTable,
          Area,
          $$AreasTableFilterComposer,
          $$AreasTableOrderingComposer,
          $$AreasTableAnnotationComposer,
          $$AreasTableCreateCompanionBuilder,
          $$AreasTableUpdateCompanionBuilder,
          (Area, BaseReferences<_$AppDatabase, $AreasTable, Area>),
          Area,
          PrefetchHooks Function()
        > {
  $$AreasTableTableManager(_$AppDatabase db, $AreasTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AreasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AreasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AreasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => AreasCompanion(
                id: id,
                name: name,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String?> description = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => AreasCompanion.insert(
                id: id,
                name: name,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AreasTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AreasTable,
      Area,
      $$AreasTableFilterComposer,
      $$AreasTableOrderingComposer,
      $$AreasTableAnnotationComposer,
      $$AreasTableCreateCompanionBuilder,
      $$AreasTableUpdateCompanionBuilder,
      (Area, BaseReferences<_$AppDatabase, $AreasTable, Area>),
      Area,
      PrefetchHooks Function()
    >;
typedef $$AreaTablesTableCreateCompanionBuilder =
    AreaTablesCompanion Function({
      Value<int> id,
      required String name,
      Value<String> tableState,
      Value<String?> description,
      Value<int> capacity,
      Value<int?> areaId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int?> orderId,
    });
typedef $$AreaTablesTableUpdateCompanionBuilder =
    AreaTablesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> tableState,
      Value<String?> description,
      Value<int> capacity,
      Value<int?> areaId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int?> orderId,
    });

class $$AreaTablesTableFilterComposer
    extends Composer<_$AppDatabase, $AreaTablesTable> {
  $$AreaTablesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tableState => $composableBuilder(
    column: $table.tableState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get capacity => $composableBuilder(
    column: $table.capacity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get areaId => $composableBuilder(
    column: $table.areaId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AreaTablesTableOrderingComposer
    extends Composer<_$AppDatabase, $AreaTablesTable> {
  $$AreaTablesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tableState => $composableBuilder(
    column: $table.tableState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get capacity => $composableBuilder(
    column: $table.capacity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get areaId => $composableBuilder(
    column: $table.areaId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AreaTablesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AreaTablesTable> {
  $$AreaTablesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get tableState => $composableBuilder(
    column: $table.tableState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get capacity =>
      $composableBuilder(column: $table.capacity, builder: (column) => column);

  GeneratedColumn<int> get areaId =>
      $composableBuilder(column: $table.areaId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get orderId =>
      $composableBuilder(column: $table.orderId, builder: (column) => column);
}

class $$AreaTablesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AreaTablesTable,
          AreaTable,
          $$AreaTablesTableFilterComposer,
          $$AreaTablesTableOrderingComposer,
          $$AreaTablesTableAnnotationComposer,
          $$AreaTablesTableCreateCompanionBuilder,
          $$AreaTablesTableUpdateCompanionBuilder,
          (
            AreaTable,
            BaseReferences<_$AppDatabase, $AreaTablesTable, AreaTable>,
          ),
          AreaTable,
          PrefetchHooks Function()
        > {
  $$AreaTablesTableTableManager(_$AppDatabase db, $AreaTablesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AreaTablesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AreaTablesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AreaTablesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> tableState = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<int> capacity = const Value.absent(),
                Value<int?> areaId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int?> orderId = const Value.absent(),
              }) => AreaTablesCompanion(
                id: id,
                name: name,
                tableState: tableState,
                description: description,
                capacity: capacity,
                areaId: areaId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                orderId: orderId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String> tableState = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<int> capacity = const Value.absent(),
                Value<int?> areaId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int?> orderId = const Value.absent(),
              }) => AreaTablesCompanion.insert(
                id: id,
                name: name,
                tableState: tableState,
                description: description,
                capacity: capacity,
                areaId: areaId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                orderId: orderId,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AreaTablesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AreaTablesTable,
      AreaTable,
      $$AreaTablesTableFilterComposer,
      $$AreaTablesTableOrderingComposer,
      $$AreaTablesTableAnnotationComposer,
      $$AreaTablesTableCreateCompanionBuilder,
      $$AreaTablesTableUpdateCompanionBuilder,
      (AreaTable, BaseReferences<_$AppDatabase, $AreaTablesTable, AreaTable>),
      AreaTable,
      PrefetchHooks Function()
    >;
typedef $$StationsTableCreateCompanionBuilder =
    StationsCompanion Function({
      Value<int> id,
      required String name,
      Value<String?> description,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$StationsTableUpdateCompanionBuilder =
    StationsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> description,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$StationsTableFilterComposer
    extends Composer<_$AppDatabase, $StationsTable> {
  $$StationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StationsTableOrderingComposer
    extends Composer<_$AppDatabase, $StationsTable> {
  $$StationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StationsTable> {
  $$StationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$StationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StationsTable,
          Station,
          $$StationsTableFilterComposer,
          $$StationsTableOrderingComposer,
          $$StationsTableAnnotationComposer,
          $$StationsTableCreateCompanionBuilder,
          $$StationsTableUpdateCompanionBuilder,
          (Station, BaseReferences<_$AppDatabase, $StationsTable, Station>),
          Station,
          PrefetchHooks Function()
        > {
  $$StationsTableTableManager(_$AppDatabase db, $StationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => StationsCompanion(
                id: id,
                name: name,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String?> description = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => StationsCompanion.insert(
                id: id,
                name: name,
                description: description,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StationsTable,
      Station,
      $$StationsTableFilterComposer,
      $$StationsTableOrderingComposer,
      $$StationsTableAnnotationComposer,
      $$StationsTableCreateCompanionBuilder,
      $$StationsTableUpdateCompanionBuilder,
      (Station, BaseReferences<_$AppDatabase, $StationsTable, Station>),
      Station,
      PrefetchHooks Function()
    >;
typedef $$KiosksTableCreateCompanionBuilder =
    KiosksCompanion Function({
      Value<int> id,
      required String name,
      Value<String?> description,
      Value<String?> ip,
      Value<int?> port,
      Value<String?> location,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$KiosksTableUpdateCompanionBuilder =
    KiosksCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> description,
      Value<String?> ip,
      Value<int?> port,
      Value<String?> location,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$KiosksTableFilterComposer
    extends Composer<_$AppDatabase, $KiosksTable> {
  $$KiosksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ip => $composableBuilder(
    column: $table.ip,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KiosksTableOrderingComposer
    extends Composer<_$AppDatabase, $KiosksTable> {
  $$KiosksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ip => $composableBuilder(
    column: $table.ip,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KiosksTableAnnotationComposer
    extends Composer<_$AppDatabase, $KiosksTable> {
  $$KiosksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ip =>
      $composableBuilder(column: $table.ip, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$KiosksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KiosksTable,
          Kiosk,
          $$KiosksTableFilterComposer,
          $$KiosksTableOrderingComposer,
          $$KiosksTableAnnotationComposer,
          $$KiosksTableCreateCompanionBuilder,
          $$KiosksTableUpdateCompanionBuilder,
          (Kiosk, BaseReferences<_$AppDatabase, $KiosksTable, Kiosk>),
          Kiosk,
          PrefetchHooks Function()
        > {
  $$KiosksTableTableManager(_$AppDatabase db, $KiosksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KiosksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KiosksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KiosksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> ip = const Value.absent(),
                Value<int?> port = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => KiosksCompanion(
                id: id,
                name: name,
                description: description,
                ip: ip,
                port: port,
                location: location,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String?> description = const Value.absent(),
                Value<String?> ip = const Value.absent(),
                Value<int?> port = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => KiosksCompanion.insert(
                id: id,
                name: name,
                description: description,
                ip: ip,
                port: port,
                location: location,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KiosksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KiosksTable,
      Kiosk,
      $$KiosksTableFilterComposer,
      $$KiosksTableOrderingComposer,
      $$KiosksTableAnnotationComposer,
      $$KiosksTableCreateCompanionBuilder,
      $$KiosksTableUpdateCompanionBuilder,
      (Kiosk, BaseReferences<_$AppDatabase, $KiosksTable, Kiosk>),
      Kiosk,
      PrefetchHooks Function()
    >;
typedef $$KDSsTableCreateCompanionBuilder =
    KDSsCompanion Function({
      Value<int> id,
      required String name,
      Value<String?> description,
      Value<int?> stationId,
      Value<String?> ip,
      Value<int?> port,
      Value<String?> location,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$KDSsTableUpdateCompanionBuilder =
    KDSsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> description,
      Value<int?> stationId,
      Value<String?> ip,
      Value<int?> port,
      Value<String?> location,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$KDSsTableFilterComposer extends Composer<_$AppDatabase, $KDSsTable> {
  $$KDSsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ip => $composableBuilder(
    column: $table.ip,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KDSsTableOrderingComposer extends Composer<_$AppDatabase, $KDSsTable> {
  $$KDSsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stationId => $composableBuilder(
    column: $table.stationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ip => $composableBuilder(
    column: $table.ip,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KDSsTableAnnotationComposer
    extends Composer<_$AppDatabase, $KDSsTable> {
  $$KDSsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get stationId =>
      $composableBuilder(column: $table.stationId, builder: (column) => column);

  GeneratedColumn<String> get ip =>
      $composableBuilder(column: $table.ip, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$KDSsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KDSsTable,
          KDS,
          $$KDSsTableFilterComposer,
          $$KDSsTableOrderingComposer,
          $$KDSsTableAnnotationComposer,
          $$KDSsTableCreateCompanionBuilder,
          $$KDSsTableUpdateCompanionBuilder,
          (KDS, BaseReferences<_$AppDatabase, $KDSsTable, KDS>),
          KDS,
          PrefetchHooks Function()
        > {
  $$KDSsTableTableManager(_$AppDatabase db, $KDSsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KDSsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KDSsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KDSsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<int?> stationId = const Value.absent(),
                Value<String?> ip = const Value.absent(),
                Value<int?> port = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => KDSsCompanion(
                id: id,
                name: name,
                description: description,
                stationId: stationId,
                ip: ip,
                port: port,
                location: location,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String?> description = const Value.absent(),
                Value<int?> stationId = const Value.absent(),
                Value<String?> ip = const Value.absent(),
                Value<int?> port = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => KDSsCompanion.insert(
                id: id,
                name: name,
                description: description,
                stationId: stationId,
                ip: ip,
                port: port,
                location: location,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KDSsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KDSsTable,
      KDS,
      $$KDSsTableFilterComposer,
      $$KDSsTableOrderingComposer,
      $$KDSsTableAnnotationComposer,
      $$KDSsTableCreateCompanionBuilder,
      $$KDSsTableUpdateCompanionBuilder,
      (KDS, BaseReferences<_$AppDatabase, $KDSsTable, KDS>),
      KDS,
      PrefetchHooks Function()
    >;
typedef $$CommercialsTableCreateCompanionBuilder =
    CommercialsCompanion Function({
      Value<int> id,
      required String cin,
      required String firstName,
      required String lastName,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$CommercialsTableUpdateCompanionBuilder =
    CommercialsCompanion Function({
      Value<int> id,
      Value<String> cin,
      Value<String> firstName,
      Value<String> lastName,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$CommercialsTableFilterComposer
    extends Composer<_$AppDatabase, $CommercialsTable> {
  $$CommercialsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cin => $composableBuilder(
    column: $table.cin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CommercialsTableOrderingComposer
    extends Composer<_$AppDatabase, $CommercialsTable> {
  $$CommercialsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cin => $composableBuilder(
    column: $table.cin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CommercialsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CommercialsTable> {
  $$CommercialsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cin =>
      $composableBuilder(column: $table.cin, builder: (column) => column);

  GeneratedColumn<String> get firstName =>
      $composableBuilder(column: $table.firstName, builder: (column) => column);

  GeneratedColumn<String> get lastName =>
      $composableBuilder(column: $table.lastName, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CommercialsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CommercialsTable,
          Commercial,
          $$CommercialsTableFilterComposer,
          $$CommercialsTableOrderingComposer,
          $$CommercialsTableAnnotationComposer,
          $$CommercialsTableCreateCompanionBuilder,
          $$CommercialsTableUpdateCompanionBuilder,
          (
            Commercial,
            BaseReferences<_$AppDatabase, $CommercialsTable, Commercial>,
          ),
          Commercial,
          PrefetchHooks Function()
        > {
  $$CommercialsTableTableManager(_$AppDatabase db, $CommercialsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CommercialsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CommercialsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CommercialsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> cin = const Value.absent(),
                Value<String> firstName = const Value.absent(),
                Value<String> lastName = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => CommercialsCompanion(
                id: id,
                cin: cin,
                firstName: firstName,
                lastName: lastName,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String cin,
                required String firstName,
                required String lastName,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => CommercialsCompanion.insert(
                id: id,
                cin: cin,
                firstName: firstName,
                lastName: lastName,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CommercialsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CommercialsTable,
      Commercial,
      $$CommercialsTableFilterComposer,
      $$CommercialsTableOrderingComposer,
      $$CommercialsTableAnnotationComposer,
      $$CommercialsTableCreateCompanionBuilder,
      $$CommercialsTableUpdateCompanionBuilder,
      (
        Commercial,
        BaseReferences<_$AppDatabase, $CommercialsTable, Commercial>,
      ),
      Commercial,
      PrefetchHooks Function()
    >;
typedef $$CustomersTableCreateCompanionBuilder =
    CustomersCompanion Function({
      Value<int> id,
      required String firstName,
      required String lastName,
      Value<String?> phone,
      Value<String?> email,
      Value<bool> isSynced,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$CustomersTableUpdateCompanionBuilder =
    CustomersCompanion Function({
      Value<int> id,
      Value<String> firstName,
      Value<String> lastName,
      Value<String?> phone,
      Value<String?> email,
      Value<bool> isSynced,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$CustomersTableFilterComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSynced => $composableBuilder(
    column: $table.isSynced,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CustomersTableOrderingComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSynced => $composableBuilder(
    column: $table.isSynced,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CustomersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CustomersTable> {
  $$CustomersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get firstName =>
      $composableBuilder(column: $table.firstName, builder: (column) => column);

  GeneratedColumn<String> get lastName =>
      $composableBuilder(column: $table.lastName, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<bool> get isSynced =>
      $composableBuilder(column: $table.isSynced, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CustomersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CustomersTable,
          Customer,
          $$CustomersTableFilterComposer,
          $$CustomersTableOrderingComposer,
          $$CustomersTableAnnotationComposer,
          $$CustomersTableCreateCompanionBuilder,
          $$CustomersTableUpdateCompanionBuilder,
          (Customer, BaseReferences<_$AppDatabase, $CustomersTable, Customer>),
          Customer,
          PrefetchHooks Function()
        > {
  $$CustomersTableTableManager(_$AppDatabase db, $CustomersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> firstName = const Value.absent(),
                Value<String> lastName = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<bool> isSynced = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => CustomersCompanion(
                id: id,
                firstName: firstName,
                lastName: lastName,
                phone: phone,
                email: email,
                isSynced: isSynced,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String firstName,
                required String lastName,
                Value<String?> phone = const Value.absent(),
                Value<String?> email = const Value.absent(),
                Value<bool> isSynced = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => CustomersCompanion.insert(
                id: id,
                firstName: firstName,
                lastName: lastName,
                phone: phone,
                email: email,
                isSynced: isSynced,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CustomersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CustomersTable,
      Customer,
      $$CustomersTableFilterComposer,
      $$CustomersTableOrderingComposer,
      $$CustomersTableAnnotationComposer,
      $$CustomersTableCreateCompanionBuilder,
      $$CustomersTableUpdateCompanionBuilder,
      (Customer, BaseReferences<_$AppDatabase, $CustomersTable, Customer>),
      Customer,
      PrefetchHooks Function()
    >;
typedef $$OrdersTableCreateCompanionBuilder =
    OrdersCompanion Function({
      Value<int> id,
      required String code,
      Value<String> status,
      Value<String> type,
      Value<int> priority,
      Value<String?> coupon,
      Value<int> persons,
      Value<DateTime> date,
      Value<int?> paymentId,
      Value<int?> tableId,
      Value<String?> source,
      Value<int?> sourceId,
      Value<double> discountPercentage,
      Value<int?> createdBy,
      Value<int?> takenBy,
      Value<int?> waiterId,
      Value<int?> clientId,
      Value<int?> commercialId,
      Value<String?> note,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isSynced,
    });
typedef $$OrdersTableUpdateCompanionBuilder =
    OrdersCompanion Function({
      Value<int> id,
      Value<String> code,
      Value<String> status,
      Value<String> type,
      Value<int> priority,
      Value<String?> coupon,
      Value<int> persons,
      Value<DateTime> date,
      Value<int?> paymentId,
      Value<int?> tableId,
      Value<String?> source,
      Value<int?> sourceId,
      Value<double> discountPercentage,
      Value<int?> createdBy,
      Value<int?> takenBy,
      Value<int?> waiterId,
      Value<int?> clientId,
      Value<int?> commercialId,
      Value<String?> note,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> isSynced,
    });

final class $$OrdersTableReferences
    extends BaseReferences<_$AppDatabase, $OrdersTable, Order> {
  $$OrdersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$TicketsTable, List<Ticket>> _ticketsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.tickets,
    aliasName: $_aliasNameGenerator(db.orders.id, db.tickets.orderId),
  );

  $$TicketsTableProcessedTableManager get ticketsRefs {
    final manager = $$TicketsTableTableManager(
      $_db,
      $_db.tickets,
    ).filter((f) => f.orderId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_ticketsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$OrderLogsTable, List<OrderLog>>
  _orderLogsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.orderLogs,
    aliasName: $_aliasNameGenerator(db.orders.id, db.orderLogs.orderId),
  );

  $$OrderLogsTableProcessedTableManager get orderLogsRefs {
    final manager = $$OrderLogsTableTableManager(
      $_db,
      $_db.orderLogs,
    ).filter((f) => f.orderId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_orderLogsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$OrdersTableFilterComposer
    extends Composer<_$AppDatabase, $OrdersTable> {
  $$OrdersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coupon => $composableBuilder(
    column: $table.coupon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get persons => $composableBuilder(
    column: $table.persons,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get paymentId => $composableBuilder(
    column: $table.paymentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tableId => $composableBuilder(
    column: $table.tableId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get discountPercentage => $composableBuilder(
    column: $table.discountPercentage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get takenBy => $composableBuilder(
    column: $table.takenBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get waiterId => $composableBuilder(
    column: $table.waiterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get commercialId => $composableBuilder(
    column: $table.commercialId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSynced => $composableBuilder(
    column: $table.isSynced,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> ticketsRefs(
    Expression<bool> Function($$TicketsTableFilterComposer f) f,
  ) {
    final $$TicketsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tickets,
      getReferencedColumn: (t) => t.orderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TicketsTableFilterComposer(
            $db: $db,
            $table: $db.tickets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> orderLogsRefs(
    Expression<bool> Function($$OrderLogsTableFilterComposer f) f,
  ) {
    final $$OrderLogsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.orderLogs,
      getReferencedColumn: (t) => t.orderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OrderLogsTableFilterComposer(
            $db: $db,
            $table: $db.orderLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$OrdersTableOrderingComposer
    extends Composer<_$AppDatabase, $OrdersTable> {
  $$OrdersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priority => $composableBuilder(
    column: $table.priority,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coupon => $composableBuilder(
    column: $table.coupon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get persons => $composableBuilder(
    column: $table.persons,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get paymentId => $composableBuilder(
    column: $table.paymentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tableId => $composableBuilder(
    column: $table.tableId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get discountPercentage => $composableBuilder(
    column: $table.discountPercentage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get takenBy => $composableBuilder(
    column: $table.takenBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get waiterId => $composableBuilder(
    column: $table.waiterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get commercialId => $composableBuilder(
    column: $table.commercialId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSynced => $composableBuilder(
    column: $table.isSynced,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OrdersTableAnnotationComposer
    extends Composer<_$AppDatabase, $OrdersTable> {
  $$OrdersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<String> get coupon =>
      $composableBuilder(column: $table.coupon, builder: (column) => column);

  GeneratedColumn<int> get persons =>
      $composableBuilder(column: $table.persons, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get paymentId =>
      $composableBuilder(column: $table.paymentId, builder: (column) => column);

  GeneratedColumn<int> get tableId =>
      $composableBuilder(column: $table.tableId, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<int> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<double> get discountPercentage => $composableBuilder(
    column: $table.discountPercentage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<int> get takenBy =>
      $composableBuilder(column: $table.takenBy, builder: (column) => column);

  GeneratedColumn<int> get waiterId =>
      $composableBuilder(column: $table.waiterId, builder: (column) => column);

  GeneratedColumn<int> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<int> get commercialId => $composableBuilder(
    column: $table.commercialId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isSynced =>
      $composableBuilder(column: $table.isSynced, builder: (column) => column);

  Expression<T> ticketsRefs<T extends Object>(
    Expression<T> Function($$TicketsTableAnnotationComposer a) f,
  ) {
    final $$TicketsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.tickets,
      getReferencedColumn: (t) => t.orderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TicketsTableAnnotationComposer(
            $db: $db,
            $table: $db.tickets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> orderLogsRefs<T extends Object>(
    Expression<T> Function($$OrderLogsTableAnnotationComposer a) f,
  ) {
    final $$OrderLogsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.orderLogs,
      getReferencedColumn: (t) => t.orderId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OrderLogsTableAnnotationComposer(
            $db: $db,
            $table: $db.orderLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$OrdersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OrdersTable,
          Order,
          $$OrdersTableFilterComposer,
          $$OrdersTableOrderingComposer,
          $$OrdersTableAnnotationComposer,
          $$OrdersTableCreateCompanionBuilder,
          $$OrdersTableUpdateCompanionBuilder,
          (Order, $$OrdersTableReferences),
          Order,
          PrefetchHooks Function({bool ticketsRefs, bool orderLogsRefs})
        > {
  $$OrdersTableTableManager(_$AppDatabase db, $OrdersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OrdersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OrdersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OrdersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String?> coupon = const Value.absent(),
                Value<int> persons = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<int?> paymentId = const Value.absent(),
                Value<int?> tableId = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<int?> sourceId = const Value.absent(),
                Value<double> discountPercentage = const Value.absent(),
                Value<int?> createdBy = const Value.absent(),
                Value<int?> takenBy = const Value.absent(),
                Value<int?> waiterId = const Value.absent(),
                Value<int?> clientId = const Value.absent(),
                Value<int?> commercialId = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isSynced = const Value.absent(),
              }) => OrdersCompanion(
                id: id,
                code: code,
                status: status,
                type: type,
                priority: priority,
                coupon: coupon,
                persons: persons,
                date: date,
                paymentId: paymentId,
                tableId: tableId,
                source: source,
                sourceId: sourceId,
                discountPercentage: discountPercentage,
                createdBy: createdBy,
                takenBy: takenBy,
                waiterId: waiterId,
                clientId: clientId,
                commercialId: commercialId,
                note: note,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isSynced: isSynced,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String code,
                Value<String> status = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> priority = const Value.absent(),
                Value<String?> coupon = const Value.absent(),
                Value<int> persons = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<int?> paymentId = const Value.absent(),
                Value<int?> tableId = const Value.absent(),
                Value<String?> source = const Value.absent(),
                Value<int?> sourceId = const Value.absent(),
                Value<double> discountPercentage = const Value.absent(),
                Value<int?> createdBy = const Value.absent(),
                Value<int?> takenBy = const Value.absent(),
                Value<int?> waiterId = const Value.absent(),
                Value<int?> clientId = const Value.absent(),
                Value<int?> commercialId = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isSynced = const Value.absent(),
              }) => OrdersCompanion.insert(
                id: id,
                code: code,
                status: status,
                type: type,
                priority: priority,
                coupon: coupon,
                persons: persons,
                date: date,
                paymentId: paymentId,
                tableId: tableId,
                source: source,
                sourceId: sourceId,
                discountPercentage: discountPercentage,
                createdBy: createdBy,
                takenBy: takenBy,
                waiterId: waiterId,
                clientId: clientId,
                commercialId: commercialId,
                note: note,
                createdAt: createdAt,
                updatedAt: updatedAt,
                isSynced: isSynced,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$OrdersTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({ticketsRefs = false, orderLogsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (ticketsRefs) db.tickets,
                    if (orderLogsRefs) db.orderLogs,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (ticketsRefs)
                        await $_getPrefetchedData<Order, $OrdersTable, Ticket>(
                          currentTable: table,
                          referencedTable: $$OrdersTableReferences
                              ._ticketsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$OrdersTableReferences(
                                db,
                                table,
                                p0,
                              ).ticketsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.orderId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (orderLogsRefs)
                        await $_getPrefetchedData<
                          Order,
                          $OrdersTable,
                          OrderLog
                        >(
                          currentTable: table,
                          referencedTable: $$OrdersTableReferences
                              ._orderLogsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$OrdersTableReferences(
                                db,
                                table,
                                p0,
                              ).orderLogsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.orderId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$OrdersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OrdersTable,
      Order,
      $$OrdersTableFilterComposer,
      $$OrdersTableOrderingComposer,
      $$OrdersTableAnnotationComposer,
      $$OrdersTableCreateCompanionBuilder,
      $$OrdersTableUpdateCompanionBuilder,
      (Order, $$OrdersTableReferences),
      Order,
      PrefetchHooks Function({bool ticketsRefs, bool orderLogsRefs})
    >;
typedef $$OrderProductsTableCreateCompanionBuilder =
    OrderProductsCompanion Function({
      Value<int> id,
      required int orderId,
      required int productId,
      Value<int?> variantId,
      Value<int?> ticketId,
      Value<int> quantity,
      required double unitaryPrice,
      Value<double> unitaryDiscount,
      Value<double> unitaryTva,
      Value<double> manualDiscount,
      Value<String?> note,
      Value<String> state,
      Value<DateTime> updatedAt,
    });
typedef $$OrderProductsTableUpdateCompanionBuilder =
    OrderProductsCompanion Function({
      Value<int> id,
      Value<int> orderId,
      Value<int> productId,
      Value<int?> variantId,
      Value<int?> ticketId,
      Value<int> quantity,
      Value<double> unitaryPrice,
      Value<double> unitaryDiscount,
      Value<double> unitaryTva,
      Value<double> manualDiscount,
      Value<String?> note,
      Value<String> state,
      Value<DateTime> updatedAt,
    });

class $$OrderProductsTableFilterComposer
    extends Composer<_$AppDatabase, $OrderProductsTable> {
  $$OrderProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get variantId => $composableBuilder(
    column: $table.variantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ticketId => $composableBuilder(
    column: $table.ticketId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get unitaryPrice => $composableBuilder(
    column: $table.unitaryPrice,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get unitaryDiscount => $composableBuilder(
    column: $table.unitaryDiscount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get unitaryTva => $composableBuilder(
    column: $table.unitaryTva,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get manualDiscount => $composableBuilder(
    column: $table.manualDiscount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OrderProductsTableOrderingComposer
    extends Composer<_$AppDatabase, $OrderProductsTable> {
  $$OrderProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderId => $composableBuilder(
    column: $table.orderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get variantId => $composableBuilder(
    column: $table.variantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ticketId => $composableBuilder(
    column: $table.ticketId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get unitaryPrice => $composableBuilder(
    column: $table.unitaryPrice,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get unitaryDiscount => $composableBuilder(
    column: $table.unitaryDiscount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get unitaryTva => $composableBuilder(
    column: $table.unitaryTva,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get manualDiscount => $composableBuilder(
    column: $table.manualDiscount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OrderProductsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OrderProductsTable> {
  $$OrderProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get orderId =>
      $composableBuilder(column: $table.orderId, builder: (column) => column);

  GeneratedColumn<int> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<int> get variantId =>
      $composableBuilder(column: $table.variantId, builder: (column) => column);

  GeneratedColumn<int> get ticketId =>
      $composableBuilder(column: $table.ticketId, builder: (column) => column);

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<double> get unitaryPrice => $composableBuilder(
    column: $table.unitaryPrice,
    builder: (column) => column,
  );

  GeneratedColumn<double> get unitaryDiscount => $composableBuilder(
    column: $table.unitaryDiscount,
    builder: (column) => column,
  );

  GeneratedColumn<double> get unitaryTva => $composableBuilder(
    column: $table.unitaryTva,
    builder: (column) => column,
  );

  GeneratedColumn<double> get manualDiscount => $composableBuilder(
    column: $table.manualDiscount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$OrderProductsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OrderProductsTable,
          OrderProduct,
          $$OrderProductsTableFilterComposer,
          $$OrderProductsTableOrderingComposer,
          $$OrderProductsTableAnnotationComposer,
          $$OrderProductsTableCreateCompanionBuilder,
          $$OrderProductsTableUpdateCompanionBuilder,
          (
            OrderProduct,
            BaseReferences<_$AppDatabase, $OrderProductsTable, OrderProduct>,
          ),
          OrderProduct,
          PrefetchHooks Function()
        > {
  $$OrderProductsTableTableManager(_$AppDatabase db, $OrderProductsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OrderProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OrderProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OrderProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> orderId = const Value.absent(),
                Value<int> productId = const Value.absent(),
                Value<int?> variantId = const Value.absent(),
                Value<int?> ticketId = const Value.absent(),
                Value<int> quantity = const Value.absent(),
                Value<double> unitaryPrice = const Value.absent(),
                Value<double> unitaryDiscount = const Value.absent(),
                Value<double> unitaryTva = const Value.absent(),
                Value<double> manualDiscount = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => OrderProductsCompanion(
                id: id,
                orderId: orderId,
                productId: productId,
                variantId: variantId,
                ticketId: ticketId,
                quantity: quantity,
                unitaryPrice: unitaryPrice,
                unitaryDiscount: unitaryDiscount,
                unitaryTva: unitaryTva,
                manualDiscount: manualDiscount,
                note: note,
                state: state,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int orderId,
                required int productId,
                Value<int?> variantId = const Value.absent(),
                Value<int?> ticketId = const Value.absent(),
                Value<int> quantity = const Value.absent(),
                required double unitaryPrice,
                Value<double> unitaryDiscount = const Value.absent(),
                Value<double> unitaryTva = const Value.absent(),
                Value<double> manualDiscount = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => OrderProductsCompanion.insert(
                id: id,
                orderId: orderId,
                productId: productId,
                variantId: variantId,
                ticketId: ticketId,
                quantity: quantity,
                unitaryPrice: unitaryPrice,
                unitaryDiscount: unitaryDiscount,
                unitaryTva: unitaryTva,
                manualDiscount: manualDiscount,
                note: note,
                state: state,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OrderProductsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OrderProductsTable,
      OrderProduct,
      $$OrderProductsTableFilterComposer,
      $$OrderProductsTableOrderingComposer,
      $$OrderProductsTableAnnotationComposer,
      $$OrderProductsTableCreateCompanionBuilder,
      $$OrderProductsTableUpdateCompanionBuilder,
      (
        OrderProduct,
        BaseReferences<_$AppDatabase, $OrderProductsTable, OrderProduct>,
      ),
      OrderProduct,
      PrefetchHooks Function()
    >;
typedef $$OrderProductComponentsTableCreateCompanionBuilder =
    OrderProductComponentsCompanion Function({
      Value<int> id,
      required int componentId,
      required int orderProductId,
      Value<int> quantity,
      Value<double> price,
      Value<bool> isSpecial,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$OrderProductComponentsTableUpdateCompanionBuilder =
    OrderProductComponentsCompanion Function({
      Value<int> id,
      Value<int> componentId,
      Value<int> orderProductId,
      Value<int> quantity,
      Value<double> price,
      Value<bool> isSpecial,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$OrderProductComponentsTableFilterComposer
    extends Composer<_$AppDatabase, $OrderProductComponentsTable> {
  $$OrderProductComponentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get componentId => $composableBuilder(
    column: $table.componentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get orderProductId => $composableBuilder(
    column: $table.orderProductId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSpecial => $composableBuilder(
    column: $table.isSpecial,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OrderProductComponentsTableOrderingComposer
    extends Composer<_$AppDatabase, $OrderProductComponentsTable> {
  $$OrderProductComponentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get componentId => $composableBuilder(
    column: $table.componentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get orderProductId => $composableBuilder(
    column: $table.orderProductId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get price => $composableBuilder(
    column: $table.price,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSpecial => $composableBuilder(
    column: $table.isSpecial,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OrderProductComponentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OrderProductComponentsTable> {
  $$OrderProductComponentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get componentId => $composableBuilder(
    column: $table.componentId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get orderProductId => $composableBuilder(
    column: $table.orderProductId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<bool> get isSpecial =>
      $composableBuilder(column: $table.isSpecial, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$OrderProductComponentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OrderProductComponentsTable,
          OrderProductComponent,
          $$OrderProductComponentsTableFilterComposer,
          $$OrderProductComponentsTableOrderingComposer,
          $$OrderProductComponentsTableAnnotationComposer,
          $$OrderProductComponentsTableCreateCompanionBuilder,
          $$OrderProductComponentsTableUpdateCompanionBuilder,
          (
            OrderProductComponent,
            BaseReferences<
              _$AppDatabase,
              $OrderProductComponentsTable,
              OrderProductComponent
            >,
          ),
          OrderProductComponent,
          PrefetchHooks Function()
        > {
  $$OrderProductComponentsTableTableManager(
    _$AppDatabase db,
    $OrderProductComponentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OrderProductComponentsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$OrderProductComponentsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OrderProductComponentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> componentId = const Value.absent(),
                Value<int> orderProductId = const Value.absent(),
                Value<int> quantity = const Value.absent(),
                Value<double> price = const Value.absent(),
                Value<bool> isSpecial = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => OrderProductComponentsCompanion(
                id: id,
                componentId: componentId,
                orderProductId: orderProductId,
                quantity: quantity,
                price: price,
                isSpecial: isSpecial,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int componentId,
                required int orderProductId,
                Value<int> quantity = const Value.absent(),
                Value<double> price = const Value.absent(),
                Value<bool> isSpecial = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => OrderProductComponentsCompanion.insert(
                id: id,
                componentId: componentId,
                orderProductId: orderProductId,
                quantity: quantity,
                price: price,
                isSpecial: isSpecial,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OrderProductComponentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OrderProductComponentsTable,
      OrderProductComponent,
      $$OrderProductComponentsTableFilterComposer,
      $$OrderProductComponentsTableOrderingComposer,
      $$OrderProductComponentsTableAnnotationComposer,
      $$OrderProductComponentsTableCreateCompanionBuilder,
      $$OrderProductComponentsTableUpdateCompanionBuilder,
      (
        OrderProductComponent,
        BaseReferences<
          _$AppDatabase,
          $OrderProductComponentsTable,
          OrderProductComponent
        >,
      ),
      OrderProductComponent,
      PrefetchHooks Function()
    >;
typedef $$PaymentsTableCreateCompanionBuilder =
    PaymentsCompanion Function({
      Value<int> id,
      Value<DateTime> date,
      required String code,
      required double amount,
      Value<String?> metaData,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$PaymentsTableUpdateCompanionBuilder =
    PaymentsCompanion Function({
      Value<int> id,
      Value<DateTime> date,
      Value<String> code,
      Value<double> amount,
      Value<String?> metaData,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$PaymentsTableFilterComposer
    extends Composer<_$AppDatabase, $PaymentsTable> {
  $$PaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metaData => $composableBuilder(
    column: $table.metaData,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PaymentsTableOrderingComposer
    extends Composer<_$AppDatabase, $PaymentsTable> {
  $$PaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metaData => $composableBuilder(
    column: $table.metaData,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PaymentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PaymentsTable> {
  $$PaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get metaData =>
      $composableBuilder(column: $table.metaData, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PaymentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PaymentsTable,
          Payment,
          $$PaymentsTableFilterComposer,
          $$PaymentsTableOrderingComposer,
          $$PaymentsTableAnnotationComposer,
          $$PaymentsTableCreateCompanionBuilder,
          $$PaymentsTableUpdateCompanionBuilder,
          (Payment, BaseReferences<_$AppDatabase, $PaymentsTable, Payment>),
          Payment,
          PrefetchHooks Function()
        > {
  $$PaymentsTableTableManager(_$AppDatabase db, $PaymentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PaymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PaymentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<double> amount = const Value.absent(),
                Value<String?> metaData = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PaymentsCompanion(
                id: id,
                date: date,
                code: code,
                amount: amount,
                metaData: metaData,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                required String code,
                required double amount,
                Value<String?> metaData = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PaymentsCompanion.insert(
                id: id,
                date: date,
                code: code,
                amount: amount,
                metaData: metaData,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PaymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PaymentsTable,
      Payment,
      $$PaymentsTableFilterComposer,
      $$PaymentsTableOrderingComposer,
      $$PaymentsTableAnnotationComposer,
      $$PaymentsTableCreateCompanionBuilder,
      $$PaymentsTableUpdateCompanionBuilder,
      (Payment, BaseReferences<_$AppDatabase, $PaymentsTable, Payment>),
      Payment,
      PrefetchHooks Function()
    >;
typedef $$TransactionsTableCreateCompanionBuilder =
    TransactionsCompanion Function({
      Value<int> id,
      required int paymentId,
      Value<String?> referenceId,
      required double amount,
      Value<DateTime> date,
      required String type,
      Value<String?> metaData,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$TransactionsTableUpdateCompanionBuilder =
    TransactionsCompanion Function({
      Value<int> id,
      Value<int> paymentId,
      Value<String?> referenceId,
      Value<double> amount,
      Value<DateTime> date,
      Value<String> type,
      Value<String?> metaData,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$TransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get paymentId => $composableBuilder(
    column: $table.paymentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get referenceId => $composableBuilder(
    column: $table.referenceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metaData => $composableBuilder(
    column: $table.metaData,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get paymentId => $composableBuilder(
    column: $table.paymentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get referenceId => $composableBuilder(
    column: $table.referenceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metaData => $composableBuilder(
    column: $table.metaData,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get paymentId =>
      $composableBuilder(column: $table.paymentId, builder: (column) => column);

  GeneratedColumn<String> get referenceId => $composableBuilder(
    column: $table.referenceId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get metaData =>
      $composableBuilder(column: $table.metaData, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$TransactionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransactionsTable,
          Transaction,
          $$TransactionsTableFilterComposer,
          $$TransactionsTableOrderingComposer,
          $$TransactionsTableAnnotationComposer,
          $$TransactionsTableCreateCompanionBuilder,
          $$TransactionsTableUpdateCompanionBuilder,
          (
            Transaction,
            BaseReferences<_$AppDatabase, $TransactionsTable, Transaction>,
          ),
          Transaction,
          PrefetchHooks Function()
        > {
  $$TransactionsTableTableManager(_$AppDatabase db, $TransactionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> paymentId = const Value.absent(),
                Value<String?> referenceId = const Value.absent(),
                Value<double> amount = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> metaData = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => TransactionsCompanion(
                id: id,
                paymentId: paymentId,
                referenceId: referenceId,
                amount: amount,
                date: date,
                type: type,
                metaData: metaData,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int paymentId,
                Value<String?> referenceId = const Value.absent(),
                required double amount,
                Value<DateTime> date = const Value.absent(),
                required String type,
                Value<String?> metaData = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => TransactionsCompanion.insert(
                id: id,
                paymentId: paymentId,
                referenceId: referenceId,
                amount: amount,
                date: date,
                type: type,
                metaData: metaData,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransactionsTable,
      Transaction,
      $$TransactionsTableFilterComposer,
      $$TransactionsTableOrderingComposer,
      $$TransactionsTableAnnotationComposer,
      $$TransactionsTableCreateCompanionBuilder,
      $$TransactionsTableUpdateCompanionBuilder,
      (
        Transaction,
        BaseReferences<_$AppDatabase, $TransactionsTable, Transaction>,
      ),
      Transaction,
      PrefetchHooks Function()
    >;
typedef $$CashSessionsTableCreateCompanionBuilder =
    CashSessionsCompanion Function({
      Value<int> id,
      required String code,
      required int cashierId,
      Value<DateTime> startedAt,
      Value<DateTime?> endedAt,
      Value<DateTime?> pausedAt,
      required double moneyAtStart,
      Value<double?> moneyAtEnd,
      Value<String> status,
      Value<bool> isSynced,
      Value<DateTime> updatedAt,
    });
typedef $$CashSessionsTableUpdateCompanionBuilder =
    CashSessionsCompanion Function({
      Value<int> id,
      Value<String> code,
      Value<int> cashierId,
      Value<DateTime> startedAt,
      Value<DateTime?> endedAt,
      Value<DateTime?> pausedAt,
      Value<double> moneyAtStart,
      Value<double?> moneyAtEnd,
      Value<String> status,
      Value<bool> isSynced,
      Value<DateTime> updatedAt,
    });

class $$CashSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $CashSessionsTable> {
  $$CashSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cashierId => $composableBuilder(
    column: $table.cashierId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get pausedAt => $composableBuilder(
    column: $table.pausedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get moneyAtStart => $composableBuilder(
    column: $table.moneyAtStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get moneyAtEnd => $composableBuilder(
    column: $table.moneyAtEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSynced => $composableBuilder(
    column: $table.isSynced,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CashSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CashSessionsTable> {
  $$CashSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cashierId => $composableBuilder(
    column: $table.cashierId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get pausedAt => $composableBuilder(
    column: $table.pausedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get moneyAtStart => $composableBuilder(
    column: $table.moneyAtStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get moneyAtEnd => $composableBuilder(
    column: $table.moneyAtEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSynced => $composableBuilder(
    column: $table.isSynced,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CashSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CashSessionsTable> {
  $$CashSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<int> get cashierId =>
      $composableBuilder(column: $table.cashierId, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get pausedAt =>
      $composableBuilder(column: $table.pausedAt, builder: (column) => column);

  GeneratedColumn<double> get moneyAtStart => $composableBuilder(
    column: $table.moneyAtStart,
    builder: (column) => column,
  );

  GeneratedColumn<double> get moneyAtEnd => $composableBuilder(
    column: $table.moneyAtEnd,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get isSynced =>
      $composableBuilder(column: $table.isSynced, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CashSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CashSessionsTable,
          CashSession,
          $$CashSessionsTableFilterComposer,
          $$CashSessionsTableOrderingComposer,
          $$CashSessionsTableAnnotationComposer,
          $$CashSessionsTableCreateCompanionBuilder,
          $$CashSessionsTableUpdateCompanionBuilder,
          (
            CashSession,
            BaseReferences<_$AppDatabase, $CashSessionsTable, CashSession>,
          ),
          CashSession,
          PrefetchHooks Function()
        > {
  $$CashSessionsTableTableManager(_$AppDatabase db, $CashSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CashSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CashSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CashSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<int> cashierId = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<DateTime?> pausedAt = const Value.absent(),
                Value<double> moneyAtStart = const Value.absent(),
                Value<double?> moneyAtEnd = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> isSynced = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => CashSessionsCompanion(
                id: id,
                code: code,
                cashierId: cashierId,
                startedAt: startedAt,
                endedAt: endedAt,
                pausedAt: pausedAt,
                moneyAtStart: moneyAtStart,
                moneyAtEnd: moneyAtEnd,
                status: status,
                isSynced: isSynced,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String code,
                required int cashierId,
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<DateTime?> pausedAt = const Value.absent(),
                required double moneyAtStart,
                Value<double?> moneyAtEnd = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> isSynced = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => CashSessionsCompanion.insert(
                id: id,
                code: code,
                cashierId: cashierId,
                startedAt: startedAt,
                endedAt: endedAt,
                pausedAt: pausedAt,
                moneyAtStart: moneyAtStart,
                moneyAtEnd: moneyAtEnd,
                status: status,
                isSynced: isSynced,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CashSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CashSessionsTable,
      CashSession,
      $$CashSessionsTableFilterComposer,
      $$CashSessionsTableOrderingComposer,
      $$CashSessionsTableAnnotationComposer,
      $$CashSessionsTableCreateCompanionBuilder,
      $$CashSessionsTableUpdateCompanionBuilder,
      (
        CashSession,
        BaseReferences<_$AppDatabase, $CashSessionsTable, CashSession>,
      ),
      CashSession,
      PrefetchHooks Function()
    >;
typedef $$TicketsTableCreateCompanionBuilder =
    TicketsCompanion Function({
      Value<int> id,
      required String num,
      Value<DateTime> date,
      required int orderId,
      Value<int?> sessionId,
      Value<int> printCount,
      required String paymentMethod,
      required double amount,
      Value<bool> isPaid,
      Value<bool> isSynced,
      Value<DateTime> updatedAt,
    });
typedef $$TicketsTableUpdateCompanionBuilder =
    TicketsCompanion Function({
      Value<int> id,
      Value<String> num,
      Value<DateTime> date,
      Value<int> orderId,
      Value<int?> sessionId,
      Value<int> printCount,
      Value<String> paymentMethod,
      Value<double> amount,
      Value<bool> isPaid,
      Value<bool> isSynced,
      Value<DateTime> updatedAt,
    });

final class $$TicketsTableReferences
    extends BaseReferences<_$AppDatabase, $TicketsTable, Ticket> {
  $$TicketsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $OrdersTable _orderIdTable(_$AppDatabase db) => db.orders.createAlias(
    $_aliasNameGenerator(db.tickets.orderId, db.orders.id),
  );

  $$OrdersTableProcessedTableManager get orderId {
    final $_column = $_itemColumn<int>('order_id')!;

    final manager = $$OrdersTableTableManager(
      $_db,
      $_db.orders,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_orderIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TicketsTableFilterComposer
    extends Composer<_$AppDatabase, $TicketsTable> {
  $$TicketsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get num => $composableBuilder(
    column: $table.num,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get printCount => $composableBuilder(
    column: $table.printCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPaid => $composableBuilder(
    column: $table.isPaid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isSynced => $composableBuilder(
    column: $table.isSynced,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$OrdersTableFilterComposer get orderId {
    final $$OrdersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.orderId,
      referencedTable: $db.orders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OrdersTableFilterComposer(
            $db: $db,
            $table: $db.orders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TicketsTableOrderingComposer
    extends Composer<_$AppDatabase, $TicketsTable> {
  $$TicketsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get num => $composableBuilder(
    column: $table.num,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get printCount => $composableBuilder(
    column: $table.printCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPaid => $composableBuilder(
    column: $table.isPaid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isSynced => $composableBuilder(
    column: $table.isSynced,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$OrdersTableOrderingComposer get orderId {
    final $$OrdersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.orderId,
      referencedTable: $db.orders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OrdersTableOrderingComposer(
            $db: $db,
            $table: $db.orders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TicketsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TicketsTable> {
  $$TicketsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get num =>
      $composableBuilder(column: $table.num, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get printCount => $composableBuilder(
    column: $table.printCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentMethod => $composableBuilder(
    column: $table.paymentMethod,
    builder: (column) => column,
  );

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<bool> get isPaid =>
      $composableBuilder(column: $table.isPaid, builder: (column) => column);

  GeneratedColumn<bool> get isSynced =>
      $composableBuilder(column: $table.isSynced, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$OrdersTableAnnotationComposer get orderId {
    final $$OrdersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.orderId,
      referencedTable: $db.orders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OrdersTableAnnotationComposer(
            $db: $db,
            $table: $db.orders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TicketsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TicketsTable,
          Ticket,
          $$TicketsTableFilterComposer,
          $$TicketsTableOrderingComposer,
          $$TicketsTableAnnotationComposer,
          $$TicketsTableCreateCompanionBuilder,
          $$TicketsTableUpdateCompanionBuilder,
          (Ticket, $$TicketsTableReferences),
          Ticket,
          PrefetchHooks Function({bool orderId})
        > {
  $$TicketsTableTableManager(_$AppDatabase db, $TicketsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TicketsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TicketsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TicketsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> num = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<int> orderId = const Value.absent(),
                Value<int?> sessionId = const Value.absent(),
                Value<int> printCount = const Value.absent(),
                Value<String> paymentMethod = const Value.absent(),
                Value<double> amount = const Value.absent(),
                Value<bool> isPaid = const Value.absent(),
                Value<bool> isSynced = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => TicketsCompanion(
                id: id,
                num: num,
                date: date,
                orderId: orderId,
                sessionId: sessionId,
                printCount: printCount,
                paymentMethod: paymentMethod,
                amount: amount,
                isPaid: isPaid,
                isSynced: isSynced,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String num,
                Value<DateTime> date = const Value.absent(),
                required int orderId,
                Value<int?> sessionId = const Value.absent(),
                Value<int> printCount = const Value.absent(),
                required String paymentMethod,
                required double amount,
                Value<bool> isPaid = const Value.absent(),
                Value<bool> isSynced = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => TicketsCompanion.insert(
                id: id,
                num: num,
                date: date,
                orderId: orderId,
                sessionId: sessionId,
                printCount: printCount,
                paymentMethod: paymentMethod,
                amount: amount,
                isPaid: isPaid,
                isSynced: isSynced,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TicketsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({orderId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (orderId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.orderId,
                                referencedTable: $$TicketsTableReferences
                                    ._orderIdTable(db),
                                referencedColumn: $$TicketsTableReferences
                                    ._orderIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TicketsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TicketsTable,
      Ticket,
      $$TicketsTableFilterComposer,
      $$TicketsTableOrderingComposer,
      $$TicketsTableAnnotationComposer,
      $$TicketsTableCreateCompanionBuilder,
      $$TicketsTableUpdateCompanionBuilder,
      (Ticket, $$TicketsTableReferences),
      Ticket,
      PrefetchHooks Function({bool orderId})
    >;
typedef $$PendingSyncOperationsTableCreateCompanionBuilder =
    PendingSyncOperationsCompanion Function({
      Value<int> id,
      required String operationType,
      required String entityType,
      required int entityId,
      Value<int?> serverId,
      Value<String?> orderCode,
      Value<String?> ticketNum,
      Value<String?> updateData,
      Value<DateTime> createdAt,
      Value<int> retryCount,
      Value<String?> lastError,
    });
typedef $$PendingSyncOperationsTableUpdateCompanionBuilder =
    PendingSyncOperationsCompanion Function({
      Value<int> id,
      Value<String> operationType,
      Value<String> entityType,
      Value<int> entityId,
      Value<int?> serverId,
      Value<String?> orderCode,
      Value<String?> ticketNum,
      Value<String?> updateData,
      Value<DateTime> createdAt,
      Value<int> retryCount,
      Value<String?> lastError,
    });

class $$PendingSyncOperationsTableFilterComposer
    extends Composer<_$AppDatabase, $PendingSyncOperationsTable> {
  $$PendingSyncOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orderCode => $composableBuilder(
    column: $table.orderCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ticketNum => $composableBuilder(
    column: $table.ticketNum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updateData => $composableBuilder(
    column: $table.updateData,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingSyncOperationsTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingSyncOperationsTable> {
  $$PendingSyncOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orderCode => $composableBuilder(
    column: $table.orderCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ticketNum => $composableBuilder(
    column: $table.ticketNum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updateData => $composableBuilder(
    column: $table.updateData,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingSyncOperationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingSyncOperationsTable> {
  $$PendingSyncOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get operationType => $composableBuilder(
    column: $table.operationType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityType => $composableBuilder(
    column: $table.entityType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get orderCode =>
      $composableBuilder(column: $table.orderCode, builder: (column) => column);

  GeneratedColumn<String> get ticketNum =>
      $composableBuilder(column: $table.ticketNum, builder: (column) => column);

  GeneratedColumn<String> get updateData => $composableBuilder(
    column: $table.updateData,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$PendingSyncOperationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingSyncOperationsTable,
          PendingSyncOperation,
          $$PendingSyncOperationsTableFilterComposer,
          $$PendingSyncOperationsTableOrderingComposer,
          $$PendingSyncOperationsTableAnnotationComposer,
          $$PendingSyncOperationsTableCreateCompanionBuilder,
          $$PendingSyncOperationsTableUpdateCompanionBuilder,
          (
            PendingSyncOperation,
            BaseReferences<
              _$AppDatabase,
              $PendingSyncOperationsTable,
              PendingSyncOperation
            >,
          ),
          PendingSyncOperation,
          PrefetchHooks Function()
        > {
  $$PendingSyncOperationsTableTableManager(
    _$AppDatabase db,
    $PendingSyncOperationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingSyncOperationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$PendingSyncOperationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PendingSyncOperationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> operationType = const Value.absent(),
                Value<String> entityType = const Value.absent(),
                Value<int> entityId = const Value.absent(),
                Value<int?> serverId = const Value.absent(),
                Value<String?> orderCode = const Value.absent(),
                Value<String?> ticketNum = const Value.absent(),
                Value<String?> updateData = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => PendingSyncOperationsCompanion(
                id: id,
                operationType: operationType,
                entityType: entityType,
                entityId: entityId,
                serverId: serverId,
                orderCode: orderCode,
                ticketNum: ticketNum,
                updateData: updateData,
                createdAt: createdAt,
                retryCount: retryCount,
                lastError: lastError,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String operationType,
                required String entityType,
                required int entityId,
                Value<int?> serverId = const Value.absent(),
                Value<String?> orderCode = const Value.absent(),
                Value<String?> ticketNum = const Value.absent(),
                Value<String?> updateData = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => PendingSyncOperationsCompanion.insert(
                id: id,
                operationType: operationType,
                entityType: entityType,
                entityId: entityId,
                serverId: serverId,
                orderCode: orderCode,
                ticketNum: ticketNum,
                updateData: updateData,
                createdAt: createdAt,
                retryCount: retryCount,
                lastError: lastError,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingSyncOperationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingSyncOperationsTable,
      PendingSyncOperation,
      $$PendingSyncOperationsTableFilterComposer,
      $$PendingSyncOperationsTableOrderingComposer,
      $$PendingSyncOperationsTableAnnotationComposer,
      $$PendingSyncOperationsTableCreateCompanionBuilder,
      $$PendingSyncOperationsTableUpdateCompanionBuilder,
      (
        PendingSyncOperation,
        BaseReferences<
          _$AppDatabase,
          $PendingSyncOperationsTable,
          PendingSyncOperation
        >,
      ),
      PendingSyncOperation,
      PrefetchHooks Function()
    >;
typedef $$OrderLogsTableCreateCompanionBuilder =
    OrderLogsCompanion Function({
      Value<int> id,
      required int orderId,
      required String action,
      Value<String?> description,
      Value<DateTime> timestamp,
    });
typedef $$OrderLogsTableUpdateCompanionBuilder =
    OrderLogsCompanion Function({
      Value<int> id,
      Value<int> orderId,
      Value<String> action,
      Value<String?> description,
      Value<DateTime> timestamp,
    });

final class $$OrderLogsTableReferences
    extends BaseReferences<_$AppDatabase, $OrderLogsTable, OrderLog> {
  $$OrderLogsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $OrdersTable _orderIdTable(_$AppDatabase db) => db.orders.createAlias(
    $_aliasNameGenerator(db.orderLogs.orderId, db.orders.id),
  );

  $$OrdersTableProcessedTableManager get orderId {
    final $_column = $_itemColumn<int>('order_id')!;

    final manager = $$OrdersTableTableManager(
      $_db,
      $_db.orders,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_orderIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OrderLogsTableFilterComposer
    extends Composer<_$AppDatabase, $OrderLogsTable> {
  $$OrderLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  $$OrdersTableFilterComposer get orderId {
    final $$OrdersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.orderId,
      referencedTable: $db.orders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OrdersTableFilterComposer(
            $db: $db,
            $table: $db.orders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OrderLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $OrderLogsTable> {
  $$OrderLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  $$OrdersTableOrderingComposer get orderId {
    final $$OrdersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.orderId,
      referencedTable: $db.orders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OrdersTableOrderingComposer(
            $db: $db,
            $table: $db.orders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OrderLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OrderLogsTable> {
  $$OrderLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  $$OrdersTableAnnotationComposer get orderId {
    final $$OrdersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.orderId,
      referencedTable: $db.orders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OrdersTableAnnotationComposer(
            $db: $db,
            $table: $db.orders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OrderLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OrderLogsTable,
          OrderLog,
          $$OrderLogsTableFilterComposer,
          $$OrderLogsTableOrderingComposer,
          $$OrderLogsTableAnnotationComposer,
          $$OrderLogsTableCreateCompanionBuilder,
          $$OrderLogsTableUpdateCompanionBuilder,
          (OrderLog, $$OrderLogsTableReferences),
          OrderLog,
          PrefetchHooks Function({bool orderId})
        > {
  $$OrderLogsTableTableManager(_$AppDatabase db, $OrderLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OrderLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OrderLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OrderLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> orderId = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
              }) => OrderLogsCompanion(
                id: id,
                orderId: orderId,
                action: action,
                description: description,
                timestamp: timestamp,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int orderId,
                required String action,
                Value<String?> description = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
              }) => OrderLogsCompanion.insert(
                id: id,
                orderId: orderId,
                action: action,
                description: description,
                timestamp: timestamp,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$OrderLogsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({orderId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (orderId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.orderId,
                                referencedTable: $$OrderLogsTableReferences
                                    ._orderIdTable(db),
                                referencedColumn: $$OrderLogsTableReferences
                                    ._orderIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$OrderLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OrderLogsTable,
      OrderLog,
      $$OrderLogsTableFilterComposer,
      $$OrderLogsTableOrderingComposer,
      $$OrderLogsTableAnnotationComposer,
      $$OrderLogsTableCreateCompanionBuilder,
      $$OrderLogsTableUpdateCompanionBuilder,
      (OrderLog, $$OrderLogsTableReferences),
      OrderLog,
      PrefetchHooks Function({bool orderId})
    >;
typedef $$WaitersTableCreateCompanionBuilder =
    WaitersCompanion Function({
      Value<int> id,
      required String firstName,
      Value<String?> lastName,
      Value<String?> imageUrl,
      Value<String?> username,
      Value<String?> passwordHash,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$WaitersTableUpdateCompanionBuilder =
    WaitersCompanion Function({
      Value<int> id,
      Value<String> firstName,
      Value<String?> lastName,
      Value<String?> imageUrl,
      Value<String?> username,
      Value<String?> passwordHash,
      Value<bool> isActive,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$WaitersTableFilterComposer
    extends Composer<_$AppDatabase, $WaitersTable> {
  $$WaitersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get passwordHash => $composableBuilder(
    column: $table.passwordHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WaitersTableOrderingComposer
    extends Composer<_$AppDatabase, $WaitersTable> {
  $$WaitersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get passwordHash => $composableBuilder(
    column: $table.passwordHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WaitersTableAnnotationComposer
    extends Composer<_$AppDatabase, $WaitersTable> {
  $$WaitersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get firstName =>
      $composableBuilder(column: $table.firstName, builder: (column) => column);

  GeneratedColumn<String> get lastName =>
      $composableBuilder(column: $table.lastName, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get passwordHash => $composableBuilder(
    column: $table.passwordHash,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$WaitersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WaitersTable,
          Waiter,
          $$WaitersTableFilterComposer,
          $$WaitersTableOrderingComposer,
          $$WaitersTableAnnotationComposer,
          $$WaitersTableCreateCompanionBuilder,
          $$WaitersTableUpdateCompanionBuilder,
          (Waiter, BaseReferences<_$AppDatabase, $WaitersTable, Waiter>),
          Waiter,
          PrefetchHooks Function()
        > {
  $$WaitersTableTableManager(_$AppDatabase db, $WaitersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WaitersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WaitersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WaitersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> firstName = const Value.absent(),
                Value<String?> lastName = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<String?> username = const Value.absent(),
                Value<String?> passwordHash = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => WaitersCompanion(
                id: id,
                firstName: firstName,
                lastName: lastName,
                imageUrl: imageUrl,
                username: username,
                passwordHash: passwordHash,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String firstName,
                Value<String?> lastName = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<String?> username = const Value.absent(),
                Value<String?> passwordHash = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => WaitersCompanion.insert(
                id: id,
                firstName: firstName,
                lastName: lastName,
                imageUrl: imageUrl,
                username: username,
                passwordHash: passwordHash,
                isActive: isActive,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WaitersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WaitersTable,
      Waiter,
      $$WaitersTableFilterComposer,
      $$WaitersTableOrderingComposer,
      $$WaitersTableAnnotationComposer,
      $$WaitersTableCreateCompanionBuilder,
      $$WaitersTableUpdateCompanionBuilder,
      (Waiter, BaseReferences<_$AppDatabase, $WaitersTable, Waiter>),
      Waiter,
      PrefetchHooks Function()
    >;
typedef $$WaiterAreasTableCreateCompanionBuilder =
    WaiterAreasCompanion Function({
      required int waiterId,
      required int areaId,
      Value<int> rowid,
    });
typedef $$WaiterAreasTableUpdateCompanionBuilder =
    WaiterAreasCompanion Function({
      Value<int> waiterId,
      Value<int> areaId,
      Value<int> rowid,
    });

class $$WaiterAreasTableFilterComposer
    extends Composer<_$AppDatabase, $WaiterAreasTable> {
  $$WaiterAreasTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get waiterId => $composableBuilder(
    column: $table.waiterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get areaId => $composableBuilder(
    column: $table.areaId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WaiterAreasTableOrderingComposer
    extends Composer<_$AppDatabase, $WaiterAreasTable> {
  $$WaiterAreasTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get waiterId => $composableBuilder(
    column: $table.waiterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get areaId => $composableBuilder(
    column: $table.areaId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WaiterAreasTableAnnotationComposer
    extends Composer<_$AppDatabase, $WaiterAreasTable> {
  $$WaiterAreasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get waiterId =>
      $composableBuilder(column: $table.waiterId, builder: (column) => column);

  GeneratedColumn<int> get areaId =>
      $composableBuilder(column: $table.areaId, builder: (column) => column);
}

class $$WaiterAreasTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WaiterAreasTable,
          WaiterArea,
          $$WaiterAreasTableFilterComposer,
          $$WaiterAreasTableOrderingComposer,
          $$WaiterAreasTableAnnotationComposer,
          $$WaiterAreasTableCreateCompanionBuilder,
          $$WaiterAreasTableUpdateCompanionBuilder,
          (
            WaiterArea,
            BaseReferences<_$AppDatabase, $WaiterAreasTable, WaiterArea>,
          ),
          WaiterArea,
          PrefetchHooks Function()
        > {
  $$WaiterAreasTableTableManager(_$AppDatabase db, $WaiterAreasTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WaiterAreasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WaiterAreasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WaiterAreasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> waiterId = const Value.absent(),
                Value<int> areaId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WaiterAreasCompanion(
                waiterId: waiterId,
                areaId: areaId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int waiterId,
                required int areaId,
                Value<int> rowid = const Value.absent(),
              }) => WaiterAreasCompanion.insert(
                waiterId: waiterId,
                areaId: areaId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WaiterAreasTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WaiterAreasTable,
      WaiterArea,
      $$WaiterAreasTableFilterComposer,
      $$WaiterAreasTableOrderingComposer,
      $$WaiterAreasTableAnnotationComposer,
      $$WaiterAreasTableCreateCompanionBuilder,
      $$WaiterAreasTableUpdateCompanionBuilder,
      (
        WaiterArea,
        BaseReferences<_$AppDatabase, $WaiterAreasTable, WaiterArea>,
      ),
      WaiterArea,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db, _db.products);
  $$ProductVariantsTableTableManager get productVariants =>
      $$ProductVariantsTableTableManager(_db, _db.productVariants);
  $$VariantAttributeValuesTableTableManager get variantAttributeValues =>
      $$VariantAttributeValuesTableTableManager(
        _db,
        _db.variantAttributeValues,
      );
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db, _db.users);
  $$ComponentsTableTableManager get components =>
      $$ComponentsTableTableManager(_db, _db.components);
  $$ComponentGroupsTableTableManager get componentGroups =>
      $$ComponentGroupsTableTableManager(_db, _db.componentGroups);
  $$ProductComponentsTableTableManager get productComponents =>
      $$ProductComponentsTableTableManager(_db, _db.productComponents);
  $$AreasTableTableManager get areas =>
      $$AreasTableTableManager(_db, _db.areas);
  $$AreaTablesTableTableManager get areaTables =>
      $$AreaTablesTableTableManager(_db, _db.areaTables);
  $$StationsTableTableManager get stations =>
      $$StationsTableTableManager(_db, _db.stations);
  $$KiosksTableTableManager get kiosks =>
      $$KiosksTableTableManager(_db, _db.kiosks);
  $$KDSsTableTableManager get kDSs => $$KDSsTableTableManager(_db, _db.kDSs);
  $$CommercialsTableTableManager get commercials =>
      $$CommercialsTableTableManager(_db, _db.commercials);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db, _db.customers);
  $$OrdersTableTableManager get orders =>
      $$OrdersTableTableManager(_db, _db.orders);
  $$OrderProductsTableTableManager get orderProducts =>
      $$OrderProductsTableTableManager(_db, _db.orderProducts);
  $$OrderProductComponentsTableTableManager get orderProductComponents =>
      $$OrderProductComponentsTableTableManager(
        _db,
        _db.orderProductComponents,
      );
  $$PaymentsTableTableManager get payments =>
      $$PaymentsTableTableManager(_db, _db.payments);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db, _db.transactions);
  $$CashSessionsTableTableManager get cashSessions =>
      $$CashSessionsTableTableManager(_db, _db.cashSessions);
  $$TicketsTableTableManager get tickets =>
      $$TicketsTableTableManager(_db, _db.tickets);
  $$PendingSyncOperationsTableTableManager get pendingSyncOperations =>
      $$PendingSyncOperationsTableTableManager(_db, _db.pendingSyncOperations);
  $$OrderLogsTableTableManager get orderLogs =>
      $$OrderLogsTableTableManager(_db, _db.orderLogs);
  $$WaitersTableTableManager get waiters =>
      $$WaitersTableTableManager(_db, _db.waiters);
  $$WaiterAreasTableTableManager get waiterAreas =>
      $$WaiterAreasTableTableManager(_db, _db.waiterAreas);
}
