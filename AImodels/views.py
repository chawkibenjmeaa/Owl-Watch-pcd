from django.http import JsonResponse
from .services import process_image_with_text_and_ai  

def analyze_image(request, image_stream, text=None):
    try:
        # Process the image using your AI model
        result = process_image_with_text_and_ai(image_stream, text)
        
        # Return the result from the AI model
        return JsonResponse({'success': True, 'result': result})
        
    except Exception as e:
        return JsonResponse({'error': str(e)}, status=500)
