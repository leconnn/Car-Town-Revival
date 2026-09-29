// Server copy of scripts/rules/garage_grid.gd.
import type { Catalog, Dict } from "./catalog.ts";

export const CAT_WORK_BAY = 5;
export const CAT_FLOOR_TILE = 6;
export const CAT_WALL = 7;
const CAT_DOOR = 10;
const CAT_WINDOW = 11;
const NON_FLOOR = [CAT_FLOOR_TILE, CAT_WALL, CAT_DOOR, CAT_WINDOW];

export type Size = { x: number; y: number };

export function isFloorObject(def: Dict): boolean {
  return !NON_FLOOR.includes(def.category ?? 0) && (def.size_x ?? 0) > 0 && (def.size_y ?? 0) > 0;
}

export function rotatedSize(sx: number, sy: number, rot: number): Size {
  return rot % 2 === 1 ? { x: sy, y: sx } : { x: sx, y: sy };
}

export class GarageGrid {
  cells = new Map<string, string>();
  width: number;
  height: number;

  constructor(width: number, height: number) {
    this.width = width;
    this.height = height;
  }

  static build(catalog: Catalog, save: Dict): GarageGrid {
    const land = catalog.land(save.garage.land_id);
    const grid = new GarageGrid(land.size_x ?? 10, land.size_y ?? 10);
    for (const it of save.garage.items) {
      const def = catalog.item(it.item_id);
      if (!isFloorObject(def)) continue;
      grid.occupy(it.x, it.y, rotatedSize(def.size_x, def.size_y, it.rot), `item:${it.uid}`);
    }
    const carSize = catalog.tune("garage.car_size", [4, 3]);
    for (const c of save.cars) {
      if (c.placed && (c.bay_uid ?? 0) === 0) {
        grid.occupy(c.x, c.y, rotatedSize(carSize[0], carSize[1], c.rot), `car:${c.uid}`);
      }
    }
    return grid;
  }

  occupy(x: number, y: number, size: Size, k: string): void {
    for (let dx = 0; dx < size.x; dx++) {
      for (let dy = 0; dy < size.y; dy++) this.cells.set(`${x + dx},${y + dy}`, k);
    }
  }

  canPlace(x: number, y: number, size: Size, ignoreKey = ""): boolean {
    if (x < 0 || y < 0 || x + size.x > this.width || y + size.y > this.height) return false;
    for (let dx = 0; dx < size.x; dx++) {
      for (let dy = 0; dy < size.y; dy++) {
        const owner = this.cells.get(`${x + dx},${y + dy}`) ?? "";
        if (owner !== "" && owner !== ignoreKey) return false;
      }
    }
    return true;
  }

  findFree(size: Size): { x: number; y: number } {
    for (let y = 0; y < this.height - size.y + 1; y++) {
      for (let x = 0; x < this.width - size.x + 1; x++) {
        if (this.canPlace(x, y, size)) return { x, y };
      }
    }
    return { x: -1, y: -1 };
  }
}
