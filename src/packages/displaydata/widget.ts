import { RenderMimeRegistry, OutputModel } from '@jupyterlab/rendermime';
import { PanelLayout } from '@phosphor/widgets';
import { Widget } from '@phosphor/widgets';
import { nbformat } from '@jupyterlab/coreutils';
//import { IOutputModel } from '@jupyterlab/rendermime';
/**
 * The class name added to display data widgets
 */
const REVISION_CLASS = 'jp-DisplayData';

/**
 * A widget for showing output data.
 */
export class DisplayData extends Widget {
    /**
     * Construct a new code version.
     */
    constructor(options: DisplayData.IOptions) {
        super();

        //create output model with ioutputmodel options

        this.addClass(REVISION_CLASS);

        let outputModel = new OutputModel({
            value: options.model,
            trusted:true
        })
          
        //assign model to result of above and remove if statement below
        //let model = (this.model = options.model);
        let model = outputModel;
        console.log(model)
        let rendermime = (this.rendermime = options.rendermime);

        let layout = (this.layout = new PanelLayout());

        // Code borrowed from OutputArea extension.
        // TODO(andrewhead): support other types of display data.
        // TODO(andrewhead): change second argument (preferSafe) based on display data field.
        //if (nbformat.isExecuteResult(model) || nbformat.isDisplayData(model)) {

        let mimeType = rendermime.preferredMimeType(model.data, "ensure");
        let output = rendermime.createRenderer(mimeType);
        output.renderModel(model);
        layout.addWidget(output);
        //}
    }

    /**
     * The model used by the widget.
     */
    readonly model: nbformat.IOutput;

    /**
     * The rendermime instance used by the widget.
     */
    readonly rendermime: RenderMimeRegistry;
}

/**
 * A namespace for `DisplayData` statics.
 */
export namespace DisplayData {
    /**
     * The options used to create a `DisplayData`.
     */
    export interface IOptions {
        /**
         * The model of the output.
         */
        model: nbformat.IOutput;

        /**
         * The mime renderer for this widget.
         */
        rendermime: RenderMimeRegistry;
    }
}