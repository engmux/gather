import { AbstractOutputterCell } from "../packages/cell";
import { ICodeCellModel, CodeCellModel } from "@jupyterlab/cells";
//import { IOutputModel } from "@jupyterlab/rendermime";
import { UUID } from "@phosphor/coreutils";
import {nbformat} from "@jupyterlab/coreutils"
/**
 * Create a new cell with the same ID and content.
 */
export function copyICodeCellModel(cell: ICodeCellModel): ICodeCellModel {
    return new CodeCellModel({ id: cell.id, cell: cell.toJSON() });
}

/**
 * Implementation of SliceableCell for Jupyter Lab. Wrapper around the ICodeCellModel.
 */
export class LabCell extends AbstractOutputterCell {

    constructor(model: ICodeCellModel) {
        super();
        this._model = model;
    }
    
    get model(): ICodeCellModel {
        return this._model;
    }

    get id(): string {
        return this._model.id;
    }

    get persistentId(): string {
        if (!this._model.metadata.has("persistent_id")) {
            this._model.metadata.set("persistent_id", UUID.uuid4());
        }
        return this._model.metadata.get("persistent_id") as string;
    }

    get text(): string {
        return this._model.value.text;
    }

    set text(text: string) {
        this._model.value.text = text;
    }

    get executionCount(): number {
        return this._model.executionCount;
    }

    set executionCount(count: number) {
        this._model.executionCount = count;
    }

    get isCode(): boolean {
        return this._model.type == "code";
    }

    get hasError(): boolean {
        return this.output.some(o => o.type === 'error');
    }

    get output(): nbformat.IOutput[] {
        let outputs = [];
        if (this._model.outputs) {
            for (let i = 0; i < this._model.outputs.length; i++) {
                outputs.push(this._model.outputs.get(i).toJSON());
            }
            return outputs;
        }
    }

    get gathered(): boolean {
        return this._model.metadata.get("gathered") as boolean;
    }

    copy(): LabCell {
        let clonedModel = copyICodeCellModel(this._model);
        return new LabCell(clonedModel);
    }

    toJupyterJSON(): any {
        return this._model.toJSON();
    }

    is_cell: boolean = true;
    is_outputter_cell: boolean = true;
    private _model: ICodeCellModel;

}