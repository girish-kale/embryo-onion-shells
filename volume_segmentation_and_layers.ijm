run("Set Measurements...", "area mean standard redirect=None decimal=3");
//run("Set Measurements...", "area mean standard centroid center perimeter integrated redirect=None decimal=3");

folder=getDirectory("choose directory specific to the day");		files=getFileList(folder);

for (file=0; file<files.length; file++){
	setBatchMode(true);
	if (endsWith(files[file], "_stack_full.tif") ){
		open(folder+files[file]);		name=File.nameWithoutExtension;			name=substring(name, 0, indexOf(name, "_stack_full"));
		File.makeDirectory(folder+name+"/");			target=folder+name+"/";
		
		selectWindow(name+"_stack_full.tif");	run("Duplicate...", "title=[volume] duplicate channels=1-2"); // keeping Phallacidin and DAPI
		
		selectWindow("volume");		run("Split Channels");		imageCalculator("Max stack", "C1-volume","C2-volume"); // getting the most signal out of the images
		close("C2-volume");			selectWindow("C1-volume");		rename("volume");
		
		run("Gaussian Blur 3D...", "x=2 y=2 z=1"); // the blur radius is less in z, in accordance with the voxel size

		getDimensions(width, height, channels, slices, frames);		getVoxelSize(wid, hei, depth, unit);
				
		setAutoThreshold("Default dark");
		//run("Threshold...");
		setThreshold(5, 1000000000000000000000000000000.0000);
		setOption("BlackBackground", true);
		run("Convert to Mask", "method=Default background=Dark black");
		
		newImage("blank", "8-bit black", width, height, 1);
		run("Concatenate...", "  title=volume image1=volume image2=blank");
		
// Basic segmentation is now ready. At times, this also includes bright structures outside the embryo (mostly dirt).
// So, now we will try to segment the volume from the 3 orthogonal orientations, and eventually keep the intersectional volume 

		selectWindow("volume");		run("Reslice [/]...", "output="+depth+" start=Top avoid"); // y-view
		selectWindow("Reslice of volume");			rename("volume-y");
		
		selectWindow("volume");		run("Reslice [/]...", "output="+depth+" start=Left rotate avoid"); // x-view
		selectWindow("Reslice of volume");			rename("volume-x");
		
// first the volume segmentation along z-view
		selectWindow("volume");		slices=nSlices;
		
		run("Options...", "iterations=2 count=1 black do=Erode stack");
		run("Options...", "iterations=1 count=1 black do=[Fill Holes] stack");

		for (slice=0; slice<slices; slice++){ // FOR loop to go through z-slices of the thresholded volume
			selectWindow("volume");			setSlice(slice+1);			run("Measure");
			
			if (getResult("Mean")>0){ // IF statement to perform convex-hull only in the slices that have some intensity contribution
				run("Create Selection");				run("Convex Hull");
				setForegroundColor(255, 255, 255);		run("Fill", "slice");		run("Select None");
			} // IF statement to perform convex-hull only in the slices that have some intensity contribution
		} // FOR loop to go through z-slices of the thresholded volume
		
		run("Clear Results");
		
// now the volume segmentation along y-view
		selectWindow("volume-y");		slices=nSlices;
		
		run("Options...", "iterations=4 count=1 black pad do=Erode stack");
		run("Options...", "iterations=1 count=1 black do=[Fill Holes] stack");

		for (slice=0; slice<slices; slice++){ // FOR loop to go through y-slices of the thresholded volume
			selectWindow("volume-y");			setSlice(slice+1);			run("Measure");
			
			if (getResult("Mean")>0){ // IF statement to perform convex-hull only in the slices that have some intensity contribution
				run("Create Selection");				run("Convex Hull");
				setForegroundColor(255, 255, 255);		run("Fill", "slice");		run("Select None");
			} // IF statement to perform convex-hull only in the slices that have some intensity contribution
		} // FOR loop to go through y-slices of the thresholded volume
		
		run("Clear Results");
		
		selectWindow("volume-y");		run("Reslice [/]...", "output="+depth+" start=Top avoid");			close("volume-y");
		selectWindow("Reslice of volume-y");			rename("volume-y"); // reslice reverted
		
		imageCalculator("Min stack", "volume","volume-y");		close("volume-y"); // keeping the intersectional volume
		
// now the volume segmentation along x-view
		selectWindow("volume-x");		slices=nSlices;
		
		run("Options...", "iterations=4 count=1 black pad do=Erode stack");
		run("Options...", "iterations=1 count=1 black do=[Fill Holes] stack");

		for (slice=0; slice<slices; slice++){ // FOR loop to go through x-slices of the thresholded volume
			selectWindow("volume-x");			setSlice(slice+1);			run("Measure");
			
			if (getResult("Mean")>0){ // IF statement to perform convex-hull only in the slices that have some intensity contribution
				run("Create Selection");				run("Convex Hull");
				setForegroundColor(255, 255, 255);		run("Fill", "slice");		run("Select None");
			} // IF statement to perform convex-hull only in the slices that have some intensity contribution
		} // FOR loop to go through x-slices of the thresholded volume
		
		run("Clear Results");
		
		selectWindow("volume-x");		run("Reslice [/]...", "output="+depth+" start=Left rotate avoid");		close("volume-x");
		selectWindow("Reslice of volume-x");			rename("volume-x"); // reslice reverted
		
		imageCalculator("Min stack", "volume","volume-x");		close("volume-x"); // keeping the intersectional volume
		
		selectWindow("volume");		run("Make Substack...", "delete slices="+nSlices);		close("Substack*");

// volume segmentation is now finished. Saving data
		selectWindow("volume");		saveAs("Tiff...", target+name+"_volume.tif");		rename("volume");

// now, we'll generate a Euclidian Distance Map, in 3D, for all the pixels inside the embryo

		// we will make a fake full embryo, by duplicating the half embryo and stitching it with it's own mirror image (in Z)
		// This trick helps to get correct Euclidean distances.
		run("Duplicate...", "title=[volume-reverse] duplicate");		run("Reverse");
		
		run("Concatenate...", "  title=BackToBack keep image1=[volume-reverse] image2=[volume]");
		
		selectWindow("BackToBack");
		run("3D Distance Map", "map=EDT image=BackToBack mask=Same threshold=1"); // this already takes into account the voxel size
		
		run("Make Substack...", "delete slices=1-"+(nSlices/2));
		
		close("Substack*");		close("volume");		close("volume-reverse");		close("BackToBack");
		
		selectWindow("EDT");	run("Gaussian Blur 3D...", "x=2 y=2 z=1"); // the blur radius is less in z, in accordance with the voxel size
// EDM generation is now finished
//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Based on the Euclidean distance maps, now we'll generate layers, i.e. volumes between surfaces that are parallel to the surface of the 
// segmented embryo volume. In this sense, these aren't concentric circles/surfaces, as the distances are calculated from a reference surface,
// rather than a reference point/line-segment.

		cortical=8; // depth till which the nuclei will be considered to be in the cortical layer (in um)
		fallen=30; // depth till which the recently expelled nuclei reside (in um), beneath the cortical layer
		// everything else would be considered as yolk nuclei
		
		selectWindow(name+"_stack_full.tif");	run("Duplicate...", "title=[Phalla-DAPI] duplicate channels=1-2"); // keeping Phallacidin and DAPI
		close(name+"_stack_full.tif");
		
// First getting the cortical volume
		selectWindow("EDT");		run("Duplicate...", "title=EDT_cortical duplicate");		selectWindow("EDT_cortical");
		
		setAutoThreshold("Default dark");
		//run("Threshold...");
		setThreshold(0.1, cortical);	run("Convert to Mask", "method=Default background=Dark black");
		
		run("Divide...", "value=255 stack");		setMinAndMax(0, 1); // This will create a zero-one image
		
		// this calculation will allow us to keep the pixel intensities only in the current layer and set 0 everywhere else
		run("Merge Channels...", "c2=EDT_cortical c6=EDT_cortical create keep");
		imageCalculator("Multiply create stack", "Phalla-DAPI", "Composite");		close("Composite");
		selectWindow("Result of Phalla-DAPI");			rename("Phalla-DAPI_cortical");

// Now going for the sub-cortical volume containing expelled nuclei
		selectWindow("EDT");		run("Duplicate...", "title=EDT_fallen duplicate");			selectWindow("EDT_fallen");
		
		setAutoThreshold("Default dark");
		//run("Threshold...");
		setThreshold(cortical, fallen);		run("Convert to Mask", "method=Default background=Dark black");
		
		run("Divide...", "value=255 stack");		setMinAndMax(0, 1); // This will create a zero-one image
		
		// this calculation will allow us to keep the pixel intensities only in the current layer and set 0 everywhere else
		run("Merge Channels...", "c2=EDT_fallen c6=EDT_fallen create keep");
		imageCalculator("Multiply create stack", "Phalla-DAPI", "Composite");		close("Composite");
		selectWindow("Result of Phalla-DAPI");			rename("Phalla-DAPI_fallen");
		
// Finally keeping the yolk volume containing (surprise! surprise!!) yolk nuclei
		selectWindow("EDT");		rename("EDT_yolk");			selectWindow("EDT_yolk");
		
		setAutoThreshold("Default dark");
		//run("Threshold...");
		setThreshold(fallen, 100000);		run("Convert to Mask", "method=Default background=Dark black");
		
		run("Divide...", "value=255 stack");		setMinAndMax(0, 1); // This will create a zero-one image
		
		// this calculation will allow us to keep the pixel intensities only in the current layer and set 0 everywhere else
		run("Merge Channels...", "c2=EDT_yolk c6=EDT_yolk create keep");
		imageCalculator("Multiply stack", "Phalla-DAPI", "Composite");		close("Composite");
		selectWindow("Phalla-DAPI");			rename("Phalla-DAPI_yolk");

// Here we quickly combine various volumes (cortical, sub-cortical, and yolk) as different color channels in the same hyperstack
		
		// Hyperstack containing the segmented volumes themselves
		run("Merge Channels...", "c2=EDT_cortical c6=EDT_fallen c7=EDT_yolk create");
		selectWindow("Composite");		rename("volume_layers");
		
		// Hyperstacks containing various layers
		selectWindow("Phalla-DAPI_cortical");		run("Split Channels");
		selectWindow("Phalla-DAPI_fallen");		run("Split Channels");
		selectWindow("Phalla-DAPI_yolk");			run("Split Channels");
		
		run("Merge Channels...", "c2=C2-Phalla-DAPI_cortical c3=C1-Phalla-DAPI_cortical c6=C2-Phalla-DAPI_fallen create keep ignore");
		selectWindow("Composite");					rename("Phalla-DAPI_layers");			saveAs("Tiff...", target+name+"_layers.tif");
		
		run("Merge Channels...", "c1=C1-Phalla-DAPI_cortical c2=C1-Phalla-DAPI_fallen c3=C1-Phalla-DAPI_yolk c5=C2-Phalla-DAPI_yolk c6=C2-Phalla-DAPI_fallen c7=C2-Phalla-DAPI_cortical create ignore");
		selectWindow("Phalla-DAPI_cortical");		rename("Phalla-DAPI_layers_all");		saveAs("Tiff...", target+name+"_layers_all.tif");
	
	}// if (endsWith(files[file], "_stack_full.tif") )
	
	setBatchMode("exit and display");		close("*");			run("Collect Garbage");
	
}// for (file=0; file<files.length; file++)

exit();

