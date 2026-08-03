class AlignImageSize:
    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "image": ("IMAGE",),
                "multiple": ("INT", {"default": 16, "min": 1, "max": 256, "step": 1}),
            }
        }

    RETURN_TYPES = ("IMAGE",)
    FUNCTION = "align"
    CATEGORY = "image/transform"

    def align(self, image, multiple):
        height = image.shape[1]
        width = image.shape[2]
        target_height = max(multiple, height // multiple * multiple)
        target_width = max(multiple, width // multiple * multiple)
        top = (height - target_height) // 2
        left = (width - target_width) // 2
        return (image[:, top : top + target_height, left : left + target_width, :],)


NODE_CLASS_MAPPINGS = {"AlignImageSize": AlignImageSize}
NODE_DISPLAY_NAME_MAPPINGS = {"AlignImageSize": "Align Image Size"}
