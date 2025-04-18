import {anySame} from "./any";
import {Diff} from "./array";
import {isEmpty} from "./validation";

// functions sorted alphabetically

export const objDiff = <T>(obj1: Record<string, T>, obj2: Record<string, T>): Diff<T> => {
    const left: T[] = []
    const both: {left: T, right: T}[] = []
    const other = {...obj2}
    Object.entries(obj1).forEach(([k, v1]) => {
        const v2 = other[k]
        if (v2 === undefined) {
            left.push(v1)
        } else {
            both.push({left: v1, right: v2})
        }
        delete other[k]
    })
    const right: T[] = Object.values(other)
    return {left, right, both}
}

export function equalDeep<T>(a: T, b: T): boolean {
    if (typeof a === 'string' || typeof a === 'number' || typeof a === 'boolean' || typeof a === 'symbol' || a === null || a === undefined) {
        return a === b
    } else if (Array.isArray(a)) {
        return Array.isArray(b) && a.length === b.length && a.every((v, i) => equalDeep(v, b[i]))
    } else if (typeof a === 'object') {
        if (typeof b === 'object' && !Array.isArray(b) && b !== null) {
            return Object.keys(a).length === Object.keys(b).length && Object.entries(a).every(([k, v]) => equalDeep(v, b[k as keyof T]))
        }
    }
    return false
}

export function filterKeys<K extends keyof any, V, T extends Record<K, V>>(obj: T, p: (k: K) => boolean): T {
    return Object.fromEntries(Object.entries(obj).filter(([k,]) => p(k as K))) as T
}

export function filterValues<K extends keyof any, V, T extends Record<K, V>>(obj: T, p: (v: V) => boolean): T {
    return Object.fromEntries(Object.entries(obj).filter(([, v]) => p(v as V))) as T
}

export function mapEntries<T, U>(obj: Record<string, T>, f: (k: string, v: T) => U): Record<string, U> {
    return Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, f(k, v)]))
}

export function mapValues<T, U>(obj: Record<string, T>, f: (t: T) => U): Record<string, U> {
    return mapEntries(obj, (_, v) => f(v))
}

export function mapEntriesAsync<T, U>(obj: Record<string, T>, f: (k: string, v: T) => Promise<U>): Promise<Record<string, U>> {
    return Promise.all(Object.entries(obj).map(([k, v]) => f(k, v).then(u => [k, u]))).then(Object.fromEntries)
}

export function mapValuesAsync<T, U>(obj: Record<string, T>, f: (t: T) => Promise<U>): Promise<Record<string, U>> {
    return mapEntriesAsync(obj, (_, v) => f(v))
}

// remove fields from `source` if they exist and have the same value in `ref`
export function minusFieldsDeep(source: any, ref: any): any {
    if (typeof source === 'string' || typeof source === 'number' || typeof source === 'boolean' || typeof source === 'symbol' || source === null || source === undefined) {
        return source !== ref ? source : undefined
    } else if (Array.isArray(source)) {
        if (Array.isArray(ref)) {
            const arr = source.map((v, i) => minusFieldsDeep(v, ref[i]))
            return arr.some(v => v !== undefined) ? arr : undefined
        } else {
            return source
        }
    } else if (typeof source === 'object') {
        if (typeof ref === 'object' && !Array.isArray(ref) && ref !== null) {
            const obj = Object.fromEntries(Object.entries(source).map(([key, value]) => [key, minusFieldsDeep(value, ref[key])]).filter(([, v]) => v !== undefined))
            return Object.keys(obj).length > 0 ? obj : undefined
        } else {
            return source
        }
    }
}

export function objectSame(a: object, b: object): boolean {
    if (a instanceof Date && b instanceof Date) return a.getTime() === b.getTime()
    if ((a instanceof Number || a instanceof Boolean) && (b instanceof Number || b instanceof Boolean)) return a.valueOf() === b.valueOf()
    const aEntries = Object.entries(a)
    const bEntries = Object.entries(b)
    return aEntries.length === bEntries.length && aEntries.every(([key, value]) => anySame(value, (b as any)[key]))
}

export function removeEmpty<K extends keyof any, V, T extends Record<K, V>>(obj: T): T {
    return filterValues(obj, v => !isEmpty(v))
}

export function mapEntriesDeep(obj: unknown, f: (path: (string | number)[], value: unknown) => unknown, path: (string | number)[] = []): unknown {
    if (Array.isArray(obj)) {
        return obj.map((item, i) => mapEntriesDeep(item, f, [...path, i]))
    }

    if (typeof obj === 'object' && obj !== null) {
        return Object.fromEntries(Object.entries(obj).map(([key, value]) => {
            const entryPath = [...path, key]
            return [key, f(entryPath, mapEntriesDeep(value, f, entryPath))]
        }))
    }

    return obj
}

export function removeFieldsDeep(obj: any, keysToRemove: string[]): any {
    if (Array.isArray(obj)) {
        return obj.map(item => removeFieldsDeep(item, keysToRemove))
    }

    if (typeof obj === 'object' && obj !== null) {
        const res: { [key: string]: any } = {}
        Object.keys(obj).forEach(key => {
            if (keysToRemove.indexOf(key) < 0) {
                res[key] = removeFieldsDeep(obj[key], keysToRemove)
            }
        })
        return res
    }

    return obj
}

export function collectFieldsDeep(obj: any, keysToCollect: string[]): any[] {
    if (Array.isArray(obj)) {
        return obj.map(item => collectFieldsDeep(item, keysToCollect)).flat()
    }

    if (typeof obj === 'object' && obj !== null) {
        const res: any[] = []
        Object.keys(obj).forEach(key => {
            if (keysToCollect.indexOf(key) >= 0) {
                res.push(obj[key])
            } else {
                res.push(...collectFieldsDeep(obj[key], keysToCollect))
            }
        })
        return res
    }

    return []
}

export function removeUndefined<K extends keyof any, V, T extends Record<K, V>>(obj: T): T {
    return filterValues(obj, v => v !== undefined)
}
