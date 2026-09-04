/**
 * Minimal JSON contract validator.
 *
 * Written by hand on purpose. A schema library would be a production dependency added to satisfy
 * a handful of assertions, and every extra dependency in a test framework is a supply-chain and
 * maintenance cost that has to be justified. Roughly forty lines cover required keys, field types,
 * nested objects and unexpected keys, which is the whole contract surface this API exposes.
 */
export type PrimitiveType = 'string' | 'number' | 'boolean';

export type FieldSpec = PrimitiveType | SchemaSpec;

export interface SchemaSpec {
  readonly [field: string]: FieldSpec;
}

export interface ValidationOptions {
  /** When true, a key present in the response but absent from the contract is a violation. */
  readonly strict?: boolean;
}

/** Returns a list of human-readable contract violations. An empty array means the contract holds. */
export function validateSchema(
  value: unknown,
  spec: SchemaSpec,
  options: ValidationOptions = {},
  path = '$',
): string[] {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return [`${path}: expected an object, received ${describeType(value)}`];
  }

  const violations: string[] = [];
  const record = value as Record<string, unknown>;

  for (const [field, expected] of Object.entries(spec)) {
    const fieldPath = `${path}.${field}`;

    if (!(field in record)) {
      violations.push(`${fieldPath}: required key is missing`);
      continue;
    }

    const actual = record[field];

    if (typeof expected === 'string') {
      if (typeof actual !== expected) {
        violations.push(`${fieldPath}: expected ${expected}, received ${describeType(actual)}`);
      }
      continue;
    }

    violations.push(...validateSchema(actual, expected, options, fieldPath));
  }

  if (options.strict === true) {
    for (const field of Object.keys(record)) {
      if (!(field in spec)) {
        violations.push(`${path}.${field}: unexpected key, the contract does not declare it`);
      }
    }
  }

  return violations;
}

/** Same validation applied to every element of a JSON array. */
export function validateArrayOfObjects(
  value: unknown,
  itemSpec: SchemaSpec,
  options: ValidationOptions = {},
  path = '$',
): string[] {
  if (!Array.isArray(value)) {
    return [`${path}: expected an array, received ${describeType(value)}`];
  }

  return (value as unknown[]).flatMap((item, index) =>
    validateSchema(item, itemSpec, options, `${path}[${index}]`),
  );
}

function describeType(value: unknown): string {
  if (value === null) {
    return 'null';
  }
  if (Array.isArray(value)) {
    return 'array';
  }
  return typeof value;
}
