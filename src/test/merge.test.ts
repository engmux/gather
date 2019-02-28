import { expect } from "chai";
import { LocationSet } from "../slicing/Slice";
import { SlicedExecution } from "../slicing/ExecutionSlicer";
import { ICell, CellSlice } from "../packages/cell";
import {nbformat} from "@jupyterlab/coreutils"

describe('SlicedExecution', () => {

    function cell(id: string, executionCount: number, ...codeLines: string[]): ICell {
        let newCell = {
            is_cell: true,
            id: id,
            persistentId: "persistent-id",
            executionCount: executionCount,
            output:new Array <nbformat.IOutput>(),
            text: codeLines.join('\n'),
            hasError: false,
            isCode: true,
            gathered: false,
            copy: () => newCell,
            toJupyterJSON: () => {}
        };
        return newCell;
    }

    function cellSlice(cell: ICell, slice: LocationSet): CellSlice {
        return new CellSlice(cell, slice);
    }

    function location(first_line: number, first_column: number, last_line: number, last_column: number) {
        return {
            first_line: first_line,
            first_column: first_column,
            last_line: last_line,
            last_column: last_column
        };
    }

    function slicedExecution(...cellSlices: CellSlice[]) {
        return new SlicedExecution(
            new Date(),
            cellSlices
        );
    }

    describe('merge', () => {

        it('unions slices with different cells', () => {
            let slice1 = slicedExecution(
                cellSlice(
                    cell("1", 1, "a = 1"),
                    new LocationSet(location(1, 0, 1, 5))
                ));
            let slice2 = slicedExecution(
                cellSlice(
                    cell("2", 2, "b = 2"),
                    new LocationSet(location(1, 0, 1, 5))
                ));
            let merged = slice1.merge(slice2);
            expect(merged.cellSlices[0].cell.id).to.equal("1");
            expect(merged.cellSlices[1].cell.id).to.equal("2");
        });

        it('will not include the same locations from the same cell twice', () => {
            let slice1 = slicedExecution(
                cellSlice(
                    cell("1", 1, "a = 1"),
                    new LocationSet(location(1, 0, 1, 5))
                ));
            let slice2 = slicedExecution(
                cellSlice(
                    cell("1", 1, "a = 1"),
                    new LocationSet(location(1, 0, 1, 5))
                ));
            let merged = slice1.merge(slice2);
            expect(merged.cellSlices.length).to.equal(1);
            expect(merged.cellSlices[0].slice.size).to.equal(1);
        });

        it('considers the same cell with different execution counts to be different', () => {
            let slice1 = slicedExecution(
                cellSlice(
                    cell("1", 1, "a = 1"),
                    new LocationSet(location(1, 0, 1, 5))
                ));
            let slice2 = slicedExecution(
                cellSlice(
                    cell("1", 2, "a = 1"),
                    new LocationSet(location(1, 0, 1, 5))
                ));
            let merged = slice1.merge(slice2);
            expect(merged.cellSlices.length).to.equal(2);
        });

        it('will include complementary ranges from two slices of the same cell', () => {
            let slice1 = slicedExecution(
                cellSlice(
                    cell("1", 1, "a = 1"),
                    new LocationSet(location(1, 0, 1, 5))
                ));
            let slice2 = slicedExecution(
                cellSlice(
                    cell("1", 1, "a = 1"),
                    new LocationSet(location(1, 0, 1, 4))
                ));
            let merged = slice1.merge(slice2);
            expect(merged.cellSlices.length).to.equal(1);
            expect(merged.cellSlices[0].slice.size).to.equal(2);
            expect(merged.cellSlices[0].slice.items).to.deep.include(location(1, 0, 1, 5));
            expect(merged.cellSlices[0].slice.items).to.deep.include(location(1, 0, 1, 4));
        });

        it('reorders the cells in execution order', () => {
            let slice1 = slicedExecution(
                cellSlice(
                    cell("2", 2, "a = 1"),
                    new LocationSet(location(1, 0, 1, 5))
                ));
            let slice2 = slicedExecution(
                cellSlice(
                    cell("1", 1, "a = 1"),
                    new LocationSet(location(1, 0, 1, 4))
                ));
            let merged = slice1.merge(slice2);
            expect(merged.cellSlices[0].cell.executionCount).to.equal(1);
            expect(merged.cellSlices[1].cell.executionCount).to.equal(2);
        });

        it('can do an n-way merge with a bunch of cells', () => {
            let slice1 = slicedExecution(
                cellSlice(cell("1", 1, "a = 1"), new LocationSet(location(1, 0, 1, 5))),
                cellSlice(cell("2", 2, "b = 1"), new LocationSet(location(1, 0, 1, 5)))
                );
            let slice2 = slicedExecution(
                cellSlice(cell("3", 3, "c = 1"), new LocationSet(location(1, 0, 1, 5))),
                cellSlice(cell("4", 4, "d = 1"), new LocationSet(location(1, 0, 1, 5)))
                );
            let slice3 = slicedExecution(
                cellSlice(cell("5", 5, "e = 1"), new LocationSet(location(1, 0, 1, 5))),
                cellSlice(cell("6", 6, "f = 1"), new LocationSet(location(1, 0, 1, 5)))
                );
            let merged = slice1.merge(slice2, slice3);
            expect(merged.cellSlices.length).to.equal(6);
        });
    });
});