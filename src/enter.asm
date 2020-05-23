; Программа реализует запись из CLI в файл текстовых данных, не более 4096 символов, включая \r, \n и etc
; Выход из программы происходит нажатием на клавишу Esc
; Программа состоит из управляющей логики и 9 процедур
; В конец файла записывается информация согласно ТЗ

code_seg                segment
						assume  CS:code_seg,DS:code_seg,SS:code_seg 
						org     0100h	;смещение под служебную информацию, пропускаем 256 байт для MS-DOS

;УПРАВЛЯЮЩАЯ ЛОГИКА

start:                  
	call    read_file_name                       ;считываем имя файла
	call    open_file                            ;открываем файл 
	cmp     file_handler, 0000h	             ;если файл не открыт (file_handler остался тем же)
        je      exit				     ;выходим (je == если первый операнд равен второму операнду при выполнении предыдущей операции сравнения)
        mov     AH, 09h
        mov     DX, offset request_typing_string     ;где offset определяет адрес переменной
        int     21h                                  ;печатаем строку request_typing_string

read_next_character:    
	call    read_character              ;считываем символ
   	cmp     AL, 1Bh                     ;проверяем не была ли нажата кнопка esc
	je      interrupt_typing	    ;если кнопка была нажата, то вызываем прерывание
    	call    increment_counters          ;инкрементируем счетчики для итоговой статистики
    	call    write_char_to_buffer        ;записываем символ в буффер
    	cmp     buffer_position, 1000h      ;проверяем буффер на переполнение	
	jl      read_next_character
    	call    clear_buffer                ;чистим буффер
    	jmp     read_next_character

	interrupt_typing:       		;в случае если ввод был прерван
		call    clear_buffer            ;чистим буффер перед записью статистики
		call    write_statistics        ;записываем статистику
		call    clear_buffer            ;чистим буффер
		call    close_file              ;закрываем файл перед выходом

exit:                   
	int 	20h                         ;передаем управление ОС

;ВСПОМОГАТЕЛЬНЫЕ ПРОЦЕДУРЫ

;ПРОЦЕДУРА ЧТЕНИЯ ИМЕНИ ФАЙЛА

read_file_name proc near                ;пытается прочитать имя файла из префикса сегмента программы, если неудачно, читает его из консоли
	
	mov     CL, ES:[80h]
	cmp     CL, 00h                     ;проверить, пуст ли буфер args в префиксе сегмента программы
    	je      read_from_console
    	dec     CL                          ;уменьшить регистр CL, чтобы не копировать escape-последовательность возврата каретки
    	mov     SI, 82h                     ;установить регистр индекса начала на первый символ в префиксе сегмента программы
	mov     DI, offset file_name        ;установить регистр индекса назначения на первый символ в массиве file_name, offset определяет адрес переменной 

	copy_next_char_psp:			
		mov	AL, ES:[SI]
		mov     byte ptr[DI], AL            ;скопировать символ из префикса сегмента программы в массив file_name
		inc     SI                          ;перейти к следующему символу в префиксе сегмента программы
		inc     DI                          ;перейти к следующему символу в массиве file_name
		dec     CL
		cmp     CL, 00h                     ;проверить, был ли последний символ скопирован из префикса сегмента программы в массив file_name
		jg      copy_next_char_psp
		mov     AL, 00h
		mov     byte ptr[DI], AL            ;написать нулевой символ для использования массива file_name в качестве имени файла
		ret

	read_from_console:     
		mov     DX, offset request_string
		mov     AH, 09h
		int     21h                         ;напечатать request_typing_string для пользователя, чтобы он ввел имя файла
		mov     DI, offset file_name
		mov     byte ptr[DI], 80h           ;записать длину массива file_name в первый байт
		mov     DX, offset file_name
		mov     AH, 0Ah
		int     21h                         ;считать строку из консоли в массив file_name
		mov     CL, file_name[01h]          ;скопировать длину строки в регистр CL
		mov     SI, offset file_name + 2h   ;установить регистр индекса начала на первый символ строки
		mov     DI, offset file_name        ;установить регистр индекса назначения на первый символ в массиве file_name

	copy_next_char_console: 
		mov     AL, ES:[SI]
		mov     byte ptr[DI], AL            ;скопировать символ из строки в массив file_name
		inc     SI                          ;перейти к следующему символу строки
		inc     DI                          ;перейти к следующему символу в массиве file_name
		dec     CL
		cmp     CL, 00h                     ;проверить, был ли последний символ скопирован из строки в массив file_name
		jg      copy_next_char_console
		mov     AL, 00h
		mov     byte ptr[DI], AL            ;написать нулевой символ для использования массива file_name в качестве имени файла
		mov     AH, 02h
		mov     DL, 0Dh
		int     21h                         ;напечатать возврат каретки \r
		mov     DL, 0Ah
		int     21h                         ;напечатать перевод строки \n
		ret

read_file_name endp

;ПРОЦЕДУРА ОТКРЫТИЯ ФАЙЛА

open_file proc near                     ;открывает или создает файл по имени, хранящемуся в массиве file_name, обработчик хранится в переменной file_handler
    
    mov     AH, 3Ch						
    mov     CX, 0000h
    mov     DX, offset file_name
    int     21h                         ;попытка открыть файл
    jc      unable_to_open_file
    cmp     AX, 0000h
    je      unable_to_open_file
    mov     file_handler, AX            ;скопировать обработчик файла в переменную file_handler
    mov     DI, offset buffer           ;установить регистр индекса назначения на первый символ в буфере
    ret

	unable_to_open_file:    
		mov     AH, 09h
		mov     DX, offset error_string
		int     21h                         ;вывести строку ошибки на консоль
		mov     file_handler, 0000h
		ret
	
open_file endp

;ПРОЦЕДУРА ЗАКРЫТИЯ ФАЙЛА

close_file proc near                    ;закрывает файл обработчиком, хранящимся в переменной file_handler
    mov     AH, 3Eh
    mov     BX, file_handler
    int     21h                         ;закрыть файл
    ret
close_file endp

;ПРОЦЕДУРА ЧТЕНИЯ СИМВОЛА

read_character proc near                ;читает символ из консоли, результат сохраняется в регистре AL
    
    mov     AH, 01h
    int     21h
    ret
	
read_character endp

;ПРОЦЕДУРА ИНКРЕМЕНТАЦИИ СЧЕТЧИКА

increment_counters proc near            ;проверяет, соответствует ли символ из регистра AL критериям, и увеличивает счетчики, если это так
    
    mov     DX, chars_counter
    inc     DX
    mov     chars_counter, DX
    cmp     AL, 0Dh                     ;проверить, является ли символ возвратом каретки \r
    je      char_is_cr_esc_seq
    cmp     AL, 41h                     ;проверяем если символ находится перед символом 'A'
    jl      char_is_out_of_range
    cmp     AL, 5Ah                     ;проверяем если символ находится в диапазоне 'A'-'Z'
    jle     char_is_lt_symbol
    cmp     AL, 61h                     ;проверяем если символ находится в диапазоне 'Z'-'a'
    jl      char_is_out_of_range
    cmp     AL, 7Ah                     ;проверяем если символ находится в диапазоне 'a'-'z'
    jle     char_is_lt_symbol
    cmp     AL, 80h                     ;проверить если символ находится перед кириллическими буквами
    jl      char_is_out_of_range
    cmp     AL, 00AFh                   ;проверить если символ находится в диапазоне кириллических букв 'А'-'Я'
    jle     char_is_cy_symbol
    cmp     AL, 00E0h                   ;проверить если символ находится в диапазоне 'Я'-'а'
    jl      char_is_out_of_range
    cmp     AL, 00F1h                   ;проверить если символ находится в диапазоне кириллических букв 'а'-'я'
    jle     char_is_cy_symbol

	char_is_out_of_range:   
		ret

	char_is_cr_esc_seq:     
		mov     DX, cr_chars_counter
		inc     DX
		mov     cr_chars_counter, DX
		ret

	char_is_lt_symbol:      
		mov     DX, lt_chars_counter
		inc     DX
		mov     lt_chars_counter, DX
		ret

	char_is_cy_symbol:      
		mov     DX, cy_chars_counter
		inc     DX
		mov     cy_chars_counter, DX
		ret

increment_counters endp

;ПРОЦЕДУРА ЗАПИСИ СИМВОЛА в БУФФЕР

write_char_to_buffer proc near          ;записывает символ из регистра AL в буфер и переходит к следующему символу
    
    mov     byte ptr[DI], AL
    mov     DX, buffer_position
    inc     DX
    mov     buffer_position, DX
    inc     DI
    ret
	
write_char_to_buffer endp

;ПРОЦЕДУРА ОТЧИСТКИ БУФФЕРА

clear_buffer proc    near               ;записывает буфер в файл и затем очищает его
    
    mov     AH, 40h
    mov     BX, file_handler
    mov     CX, buffer_position
    mov     DX, offset buffer
    int     21h                         ;записывает буфер в файл
    mov     buffer_position, 0000h      ;сбросить переменную buffer_position
    mov     DI, offset buffer           ;установить регистр индекса назначения на первый символ в буфере
    ret
	
clear_buffer endp

;ПРОЦЕДУРА ЗАПИСИ СТАТИСТИКИ

write_statistics proc near             	;записывает статистику в буфер
    
    mov     AL, 0Dh
    call    write_char_to_buffer
    mov     CL, 25h                     ;записать строку chars_string
    mov     SI, offset chars_string
	
	chars_string_it:        
		mov     AL, ES:[SI]
		call    write_char_to_buffer
		dec     CL
		inc     SI
		cmp     CL, 00h
		jg      chars_string_it
		mov     DX, chars_counter
		call    write_word                  ;записать переменную chars_counter
		mov     AL, 0Dh
		call    write_char_to_buffer        ;записать возврат каретки \r 
		mov     CL, 24h                     ;записать строку cr_chars_string
		mov     SI, offset cr_chars_string

	cr_chars_string_it:     
		mov     AL, ES:[SI]
		call    write_char_to_buffer
		dec     CL
		inc     SI
		cmp     CL, 00h
		jg      cr_chars_string_it
		mov     DX, cr_chars_counter
		call    write_word                  ;записать переменную cr_chars_counter
		mov     AL, 0Dh
		call    write_char_to_buffer        ;записать возврат каретки \r 
		;was fixed 2Dh to 2Bh
		mov     CL, 2Bh                     ;записать строку lt_chars_string
		mov     SI, offset lt_chars_string

	lt_chars_string_it:     
		mov     AL, ES:[SI]
		call    write_char_to_buffer
		dec     CL
		inc     SI
		cmp     CL, 00h
		jg      lt_chars_string_it
		mov     DX, lt_chars_counter
		call    write_word                  ;записать переменную lt_chars_counter
		mov     AL, 0Dh
		call    write_char_to_buffer        ;записать возврат каретки \r
		;was fixed 2Dh to 2Eh
		mov     CL, 2Eh                     ;записать строку  cy_chars_string
		mov     SI, offset cy_chars_string

	cy_chars_string_it:     
		mov     AL, ES:[SI]
		call    write_char_to_buffer
		dec     CL
		inc     SI
		cmp     CL, 00h
		jg      cy_chars_string_it
		mov     DX, cy_chars_counter
		call    write_word                  ;записать переменную cy_chars_counter
		ret
write_statistics endp

;ПРОЦЕДУРА ЗАПИСИ ДЕСЯТИЧНЫХ ЦИФР В СТАТИСТИКУ

write_word proc near                    ;записывает слово из регистра DX в консоль в десятичном представлении
   
    mov     CX, DX
    mov     AX, CX
    mov     DX, 0000h
    mov     BX, 2710h
    div     BX                          ;получаем 5-ю цифру
    cmp     AX, 0000h                   ;проверяем является ли 5-ая цифра 0
    je      get_4th_digit
    or      CX, 8000h                   ;устанавливаем флаг
    mov     AH, 02h
    mov     DL, 30h
    add     AL, DL
    call    write_char_to_buffer        ;записать 5-ю цифру в буфер

	get_4th_digit:          
		mov     AX, CX
		and     AX, 7FFFh
		mov     DX, 0000h
		mov     BX, 03EBh
		div     BX                          ;получаем 5-ю и 4-ю цифры
		mov     DX, 0000h
		mov     BX, 000Ah
		div     BX                          ;получаем 4-ю цифру
		cmp     DX, 0000h                   ;проверяем является ли 4-ая цифра 0
		jg      print_4th_digit
		mov     AX, CX
		and     AX, 8000h
		cmp     AX, 8000h                   ;проверяем флаг
		je      print_4th_digit
		jmp     get_3th_digit
		
	print_4th_digit:        
		or      CX, 8000h                   ;устанавливаем флаг
		mov     AH, 02h
		add     DL, 30h
		mov     AL, DL
		call    write_char_to_buffer        ;записываем 4-ю цифру в буфер
		
	get_3th_digit:          
		mov     AX, CX
		and     AX, 7FFFh
		mov     DX, 0000h
		mov     BX, 0064h
		div     BX                          ;получаем 5-ю, 4-ю и 3-ю цифру
		mov     DX, 0000h
		mov     BX, 000Ah
		div     BX                          ;получаем 3-ю цифру
		cmp     DX, 0000h                   ;проверяем является ли 3-ая цифра 0
		jg      print_3th_digit
		mov     AX, CX
		and     AX, 8000h
		cmp     AX, 8000h                   ;проверяем флаг
		je      print_3th_digit
		jmp     get_2th_digit
		
	print_3th_digit:        
		or      CX, 8000h                   ;устанавливаем флаг
		mov     AH, 02h
		add     DL, 30h
		mov     AL, DL
		call    write_char_to_buffer        ;аписываем 3-ю цифру в буфер
		
	get_2th_digit:          
		mov     AX, CX
		and     AX, 7FFFh
		mov     DX, 0000h
		mov     BX, 000Ah
		div     BX                          ;получаем 5-ю, 4-ю, 3-ю и 2-ю цифру
		mov     DX, 0000h
		mov     BX, 000Ah
		div     BX                          ;получаем 2-ю цифру
		cmp     DX, 0000h
		jg      print_2th_digit
		mov     AX, CX
		and     AX, 8000h
		cmp     AX, 8000h                   ;проверяем флаг
		je      print_2th_digit
		jmp     get_1th_digit
		
	print_2th_digit:        
		mov     AH, 02h
		add     DL, 30h
		mov     AL, DL
		call    write_char_to_buffer        ;записываем 2-ю цифру в буфер
	
	get_1th_digit:          
		mov     AX, CX
		and     AX, 7FFFh
		mov     DX, 0000h
		mov     BX, 0001h
		div     BX                          ;получаем 5-ю, 4-ю, 3-ю, 2-ю и 1-ю цифру
		mov     BX, 000Ah
		mov     DX, 0000h
		div     BX                          ;получаем 1-ю цифру
		mov     AH, 02h
		add     DL, 30h
		mov     AL, DL
		call    write_char_to_buffer        ;записываем 1-ю цифру в буфер
		ret
		
write_word endp

;КОНСТАНТЫ, СТРОКИ И СЧЕТЧИКИ

;db == define byte - определяет переменную размером в 1 байт
;dw == define word – определяет переменную размеров в 2 байта (слово)

request_string          db      'Enter the name of file (128 characters max):', 0Dh, 0Ah, 24h ;\r \n $ - признак окончания строки
error_string            db      'The program was unable to open a file. Returning control to the operating system.', 0Dh, 0Ah, 24h
request_typing_string   db      'Type a text (has to less than 4096 symbols):', 0Dh, 0Ah, 24h
chars_string            db      'The amount of characters were typed: '
cr_chars_string         db      'The amount of strings were entered: '
lt_chars_string         db      'The amount of latin characters were typed: '
cy_chars_string         db      'The amount of cyrillic characters were typed: '
file_name               db      0080h dup(00h)		;имя файла не длинее 128 символов
file_handler			dw		0000h
buffer                  db      1000h dup(00h)      ;буффер не больше 4096 символов
buffer_position         dw      0000h
chars_counter           dw      0000h
cr_chars_counter        dw      0001h
lt_chars_counter        dw      0000h
cy_chars_counter        dw      0000h

code_seg                ends
						end     start
